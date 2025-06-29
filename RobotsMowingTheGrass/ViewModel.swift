import SwiftUI
import Combine

@MainActor
class ChatViewModel: ObservableObject
{
    // Published properties
    @Published var messages: [ChatMessage] = []
    @Published var isProcessing = false
    @Published var status = ""
    @Published var turnNumber = 0

    @Published var isClarificationPresented: Bool = false
    @Published var pendingClarificationPrompt: String? = nil

    // Settings
    @AppStorage("maxTurns") private var maxTurns: Int = 8
    @AppStorage("infiniteTurns") private var infinite: Bool = false
    @AppStorage("contextTurns") private var contextTurns: Int = 12

    // Services
    private let chatService: ChatServiceProtocol
    var configManager: ModelConfigurationManager
    private var currentTask: Task<Void, Never>?
    private var streamingCancellable: Cancellable?
    private let EndTag: String = "<conversationEnd/>"

    // Streaming state
    private var streamingMessageIndex: Int?
    private var currentModelIndex = 0

    init(
        chatService: ChatServiceProtocol = OllamaChatService(),
        configManager: ModelConfigurationManager
    ) {
        self.chatService = chatService
        self.configManager = configManager
    }

    // MARK: - Public Methods

    func sendUserMessage(_ text: String)
    {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let enabledModels = configManager.enabledConfigurations
        guard !enabledModels.isEmpty else {
            status = "No models configured"
            return
        }

        messages.append(ChatMessage.userMessage(text: trimmed))
        isProcessing = true
        status = "Starting conversation…"
        currentModelIndex = 0

        currentTask = Task {
            await runDialogueLoop(firstPrompt: trimmed, models: enabledModels)
            isProcessing = false
            status = ""
        }
    }

    func clear()
    {
        messages.removeAll()
        turnNumber = 0
        currentModelIndex = 0
        cancelCurrentOperation()
        status = ""
    }

    func cancel()
    {
        cancelCurrentOperation()
    }

    var displayMessages: [ChatMessage]
    {
        messages.flatMap { message in
            if message.isStreaming
            {
                return parseStreamingMessage(message)
            } else {
                return [message]
            }
        }
    }

    func bubbleColor(for message: ChatMessage) -> Color {
        if message.isUser {
            return .accentColor
        }

        if let config = configManager.configurations.first(where: { $0.id == message.senderID }) {
            return config.bubbleColor.color.opacity(message.isThink ? 0.15 : 0.1)
        }

        return Color.gray.opacity(0.1)
    }

    // MARK: - Private Methods

    private func parseStreamingMessage(_ message: ChatMessage) -> [ChatMessage]
    {
        let (thinkPart, mainPart) = extractThink(text: message.text)
        var result: [ChatMessage] = []

        if let thinkPart = thinkPart, !thinkPart.isEmpty
        {
            var thinkMessage = message
            thinkMessage.text = thinkPart
            thinkMessage.isThink = true
            result.append(thinkMessage)
        }

        if !mainPart.isEmpty
        {
            var mainMessage = message
            mainMessage.text = mainPart
            mainMessage.isThink = false
            result.append(mainMessage)
        } else if thinkPart == nil && !message.text.isEmpty {
            result.append(message)
        }

        return result
    }

    private func cancelCurrentOperation()
    {
        streamingCancellable?.cancel()
        currentTask?.cancel()
        currentTask = nil
        streamingMessageIndex = nil

        if isProcessing
        {
            isProcessing = false
            status = "Cancelled by user"
        }
    }

    // continuation we’ll use to wake up the async handleUserResponse
    var clarificationContinuation: CheckedContinuation<String, Never>?

    /// Scans for `<clarifyWithUser>…</clarifyWithUser>`, shows a sheet,
    /// suspends until the user replies, then returns their answer.
    func handleUserResponse(_ response: String) async -> String?
    {
        guard nil != response.range(of: "<clarifyWithUser>(.*?)</clarifyWithUser>",
                                          options: .regularExpression),
            let innerRange = response.range(of: "(?<=<clarifyWithUser>).*?(?=</clarifyWithUser>)",
                                            options: .regularExpression)
        else {
            return nil
        }

        let question = String(response[innerRange])

        pendingClarificationPrompt = question
        isClarificationPresented = true

        let answer = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            self.clarificationContinuation = continuation
        }

        pendingClarificationPrompt = nil
        isClarificationPresented = false
        clarificationContinuation = nil

        // 5) append their answer as a user message
        let userMsg = ChatMessage(
            text: answer,
            senderID: UUID(uuid:( 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
            senderName: "You",
            isThink: false,
            isStreaming: false
        )
        messages.append(userMsg)

        return answer

    }

    private func runDialogueLoop(firstPrompt: String, models: [ModelConfiguration]) async
    {
        let turnLimit = infinite ? Int.max : maxTurns
        var endFlags = 0

        turnNumber = 1
        while turnNumber < turnLimit && !Task.isCancelled && endFlags != models.count
        {
            let contextMessages = Array(messages.suffix(contextTurns))
            let historyString = buildHistoryString(from: contextMessages)

            // Get next model in round-robin fashion
            let currentModel = models[currentModelIndex % models.count]
            currentModelIndex += 1
            if currentModelIndex == models.count
            {
                currentModelIndex = 0
                turnNumber += 1
            }

            status = "\(currentModel.displayName) is thinking…"

            let systemPrompt = buildSystemPrompt(
                for: currentModel,
                isFirstResponse: turnNumber == 1,
                totalModels: models.count,
                originalPrompt: firstPrompt
            )

            let fullPrompt = systemPrompt + historyString + "\n\(currentModel.displayName):"

            if let response = await streamResponse(
                configuration: currentModel,
                prompt: fullPrompt
            ) {
//                currentPrompt = response
                if response.contains(EndTag)
                {
                    endFlags += 1
//                    let currentResponse = response.replacingOccurrences(of: EndTag, with: "")
                }

                if response.contains("<clarifyWithUser>") {
                    if let answer = await handleUserResponse(response) {
                        // incorporate `answer` into your next prompt, e.g.:
                        print("added answer to response \(answer)")
//                        response += "\nUser clarified: \(answer)\n"
                    }
                    continue  // or however you proceed in your loop
                }

//                if response.contains("<clarifyWithUser>")
//                {
//                    let user_response = await handleUserResponse(response)
//                    messages.append(user_response)
//                }
            } else {
                status = "\(currentModel.displayName) error!"
                break
            }
        }

        if endFlags >= models.count
        {
            status = "All models agreed to stop"
        }
        else
        {
            status = ""
        }

        isProcessing = false
    }

    private func streamResponse(
        configuration: ModelConfiguration,
        prompt: String
    ) async -> String?
    {
        // Create streaming message
        let streamingMessage = ChatMessage(
            text: "",
            senderID: configuration.id,
            senderName: configuration.displayName,
            isThink: false,
            isStreaming: true
        )
        messages.append(streamingMessage)
        streamingMessageIndex = messages.count - 1

        return await withCheckedContinuation { continuation in
            var accumulatedText = ""

            streamingCancellable = chatService.generateResponse(
                configuration: configuration,
                prompt: prompt,
                onChunk: { [weak self] chunk in
                    Task { @MainActor [weak self] in
                        guard let self = self,
                              let index = self.streamingMessageIndex,
                              index < self.messages.count else { return }

                        accumulatedText += chunk
                        self.messages[index].text = accumulatedText
                    }
                },
                onComplete: { [weak self] result in
                    Task { @MainActor [weak self] in
                        guard let self = self,
                              let index = self.streamingMessageIndex else { return }

                        switch result {
                        case .success(let finalText):
                            self.finalizeStreamingMessage(
                                at: index,
                                with: finalText,
                                configuration: configuration
                            )
                            continuation.resume(returning: finalText)
                        case .failure:
                            self.messages.remove(at: index)
                            continuation.resume(returning: nil)
                        }

                        self.streamingMessageIndex = nil
                    }
                }
            )
        }
    }

    private func finalizeStreamingMessage(
        at index: Int,
        with text: String,
        configuration: ModelConfiguration
    )
    {
        messages.remove(at: index)

        let (thinkPart, mainPart) = extractThink(text: text)

        if let thinkPart = thinkPart, !thinkPart.isEmpty {
            messages.insert(ChatMessage(
                text: thinkPart,
                senderID: configuration.id,
                senderName: configuration.displayName,
                isThink: true,
                isStreaming: false
            ), at: index)
        }

        let finalMainPart = mainPart.isEmpty ? text : mainPart
        if !finalMainPart.isEmpty {
            let insertIndex = thinkPart != nil ? index + 1 : index
            messages.insert(ChatMessage(
                text: finalMainPart,
                senderID: configuration.id,
                senderName: configuration.displayName,
                isThink: false,
                isStreaming: false
            ), at: insertIndex)
        }
    }

    private func buildHistoryString(from messages: [ChatMessage]) -> String
    {
        messages.map { message in
            guard message.isThink == false else { return "" }
            return message.senderName + ": " + message.text
        }.joined(separator: "\n")
    }

    private func buildSystemPrompt(
        for model: ModelConfiguration,
        isFirstResponse: Bool,
        totalModels: Int,
        originalPrompt: String
    ) -> String
    {
        guard isFirstResponse || currentModelIndex <= totalModels else { return "Original user prompt: \(originalPrompt)\n\n" }

        let modelList = configManager.enabledConfigurations
            .map { $0.displayName }
            .joined(separator: ", ")

        let basePrompt = """
        You are \(model.displayName) in a conversation between \(totalModels) AI models: (\(modelList)). \n\n
        \(model.personality.prompt)\n\n
        You will be discussing topics with the other models, taking turns to respond. 
        We are all friends here. Be relaxed, be a rebel and be creative.
        Be thoughtful and engaging in your responses. Keep it super brief and on topic !
        You can use <think></think> tags to show your reasoning process.
        If you need user to answer a question, use tag <clarifyWithUser>Message for the user</clarifyWithUser> to request further info.
        If you feel the conversation comes to conclusion and you need to abort: use the tag \(EndTag), all participants will use it to end converation. Don't give up easily tho! 
        """

        if isFirstResponse
        {
            return basePrompt + "Use the User Prompt as the starting point for your conversation.\n\n"
        }
        else
        if currentModelIndex <= totalModels
        {
            return basePrompt + "Original user prompt: \(originalPrompt)\n\n"
        }

        return ""
    }
}
