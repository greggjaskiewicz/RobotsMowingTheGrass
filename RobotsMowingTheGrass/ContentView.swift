//
//  ContentView.swift
//  RobotsMowingTheGrass
//
//  Created by Gregg Jaskiewicz on 12/06/2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct ChatMessage: Identifiable
{
    let id = UUID()
    let text: String
    let sender: Sender
    let isThink: Bool

    enum Sender
    {
        case user, modelA, modelB

        var displayTitle: String
        {
            switch self
            {
            case .user: return "User"
            case .modelA: return "Model A"
            case .modelB: return "Model B"
            }
        }
    }
}

struct ContentView: View {
    // MARK: - App Storage
    @AppStorage("portA") private var portA: Int = 11434
    @AppStorage("portB") private var portB: Int = 11435
    @AppStorage("selectedModelA") private var selectedModelA: String = ""
    @AppStorage("selectedModelB") private var selectedModelB: String = ""
    @AppStorage("maxTurns") private var maxTurns: Int = 8
    @AppStorage("infiniteTurns") private var infinite: Bool = false
    @AppStorage("contextTurns") private var contextTurns: Int = 12

    // MARK: - State
    @State private var messages: [ChatMessage] = []
    @State private var userInput: String = ""
    @State private var isProcessing = false
    @State private var status: String = ""
    @State private var isSaving = false
    @State private var turnNumber = 0
    @State private var currentChatTask: Task<Void, Never>?

    // Streaming support
    @State private var currentStreamingMessage: ChatMessage?
    @State private var streamingBuffer: String = ""
    @State private var currentStreamingTask: URLSessionDataTask?

    var body: some View {
        NavigationSplitView {
            SettingsPanel(
                portA: $portA,
                portB: $portB,
                selectedModelA: $selectedModelA,
                selectedModelB: $selectedModelB,
                maxTurns: $maxTurns,
                infinite: $infinite,
                contextTurns: $contextTurns
            )
        } detail: {
            VStack(spacing: 0) {
                controlBar
                messagesList
                statusBar
                Divider()
                inputSection
            }
            .fileExporter(
                isPresented: $isSaving,
                document: ExportChatDocument(messages: messages),
                contentType: .json,
                defaultFilename: "LlamasChat"
            ) { result in
                handleExportResult(result)
            }
        }
        .frame(minWidth: 500, minHeight: 600)
    }

    // MARK: - View Components

    private var controlBar: some View {
        HStack {
            Text("Turn: \(turnNumber)")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Button("Save As") {
                isSaving = true
            }
            .disabled(messages.isEmpty)

            Button("Clear") {
                clearChat()
            }
            .disabled(messages.isEmpty && !isProcessing)

            Button("Cancel") {
                cancelCurrentOperation()
            }
            .disabled(currentChatTask == nil)
        }
        .padding([.top, .horizontal])
    }

    private var messagesList: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(displayMessages) { message in
                        MessageBubble(message: message)
                    }
                }
                .padding()
            }
            .background(Color(NSColor.windowBackgroundColor))
            .onChange(of: displayMessages.count) { _ in
                scrollToBottom(scrollProxy)
            }
            .onChange(of: streamingBuffer) { _ in
                scrollToStreamingMessage(scrollProxy)
            }
        }
    }

    private var statusBar: some View {
        Group {
            if isProcessing || !status.isEmpty {
                HStack {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                .animation(.easeInOut(duration: 0.2), value: status)
            }
        }
    }

    private var inputSection: some View {
        HStack {
            TextField("Type your message…", text: $userInput, axis: .vertical)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .disabled(isProcessing)
                .onSubmit(sendUserMessage)
                .lineLimit(1...5)

            Button("Send") {
                sendUserMessage()
            }
            .disabled(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding()
    }

    // MARK: - Computed Properties

    private var displayMessages: [ChatMessage]
    {
        var result = messages

        if let streaming = currentStreamingMessage
        {
            print("sender: \(streaming.sender)")
            let (thinkPart, mainPart) = extractThink(text: streamingBuffer)

            if let thinkPart = thinkPart, !thinkPart.isEmpty
            {
                let thinkMessage = ChatMessage(
                    text: thinkPart,
                    sender: streaming.sender,
                    isThink: true
                )
                result.append(thinkMessage)
            }

            if !mainPart.isEmpty
            {
                let mainMessage = ChatMessage(
                    text: mainPart,
                    sender: streaming.sender,
                    isThink: false
                )
                result.append(mainMessage)
            }
            else if thinkPart == nil && !streamingBuffer.isEmpty {
                let streamMessage = ChatMessage(
                    text: streamingBuffer,
                    sender: streaming.sender,
                    isThink: false
                )
                result.append(streamMessage)
            }
        }

        return result
    }

    // MARK: - Actions

    private func sendUserMessage() {
        let trimmedInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }

        let prompt = trimmedInput
        userInput = ""
        messages.append(ChatMessage(text: prompt, sender: .user, isThink: false))

        isProcessing = true
        status = "Starting conversation…"

        currentChatTask = Task {
            await runDialogueLoop(firstPrompt: prompt)
            await MainActor.run {
                isProcessing = false
                status = ""
            }
        }
    }

    private func clearChat() {
        messages.removeAll()
        turnNumber = 0
        resetStreamingState()
        cancelCurrentOperation()
        status = ""
    }

    private func cancelCurrentOperation() {
        currentStreamingTask?.cancel()
        currentChatTask?.cancel()
        currentChatTask = nil
        resetStreamingState()
        if isProcessing {
            isProcessing = false
            status = "Cancelled by user"
        }
    }

    private func resetStreamingState() {
        currentStreamingMessage = nil
        streamingBuffer = ""
        currentStreamingTask = nil
    }

    private func scrollToBottom(_ scrollProxy: ScrollViewProxy) {
        if let last = displayMessages.last {
            withAnimation(.easeOut(duration: 0.3)) {
                scrollProxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func scrollToStreamingMessage(_ scrollProxy: ScrollViewProxy) {
        if let current = currentStreamingMessage {
            scrollProxy.scrollTo(current.id, anchor: .bottom)
        }
    }

    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            print("Chat exported to: \(url)")
        case .failure(let error):
            print("Export failed: \(error)")
        }
    }

    // MARK: - Dialogue Logic

    private func runDialogueLoop(firstPrompt: String) async
    {
        var currentPrompt = firstPrompt
        var lastSender: ChatMessage.Sender = .user
        let turnLimit = infinite ? Int.max : maxTurns

        while turnNumber < turnLimit && !Task.isCancelled
        {
            turnNumber += 1

            let contextMessages = Array(messages.suffix(contextTurns))
            let historyString = buildHistoryString(from: contextMessages)

            if lastSender == .user || lastSender == .modelB
            {
                // Model A's turn
                updateStatus("Model A is thinking…")
                lastSender = .modelA

                let systemPrompt = buildSystemPrompt(for: .modelA, isFirstTurn: turnNumber == 1)
                let fullPrompt = systemPrompt + historyString + "\nModel A:"

                if let response = await generateResponse(
                    modelName: selectedModelA,
                    prompt: fullPrompt,
                    port: portA,
                    sender: .modelA
                ) {
                    currentPrompt = response
                } else {
                    updateStatus("Model A error!")
                    break
                }
            } else {
                // Model B's turn
                updateStatus("Model B is thinking…")
                lastSender = .modelB

                let systemPrompt = buildSystemPrompt(for: .modelB, isFirstTurn: turnNumber == 2)
                let fullPrompt: String

                if turnNumber == 2 {
                    // For the first Model B response, include the original prompt for context
                    fullPrompt = systemPrompt + "Original user prompt: \(firstPrompt)\n\n" + historyString + "\nModel B:"
                } else {
                    fullPrompt = systemPrompt + historyString + "\nModel B:"
                }

                if let response = await generateResponse(
                    modelName: selectedModelB,
                    prompt: fullPrompt,
                    port: portB,
                    sender: .modelB
                ) {
                    currentPrompt = response
                } else {
                    updateStatus("Model B error!")
                    break
                }
            }
        }

        updateStatus("")
    }

    private func buildHistoryString(from messages: [ChatMessage]) -> String {
        return messages.map { message in
            let sender = message.sender.displayTitle
            let prefix = message.isThink ? "[Thinking] " : ""
            return "\(sender): \(prefix)\(message.text)"
        }.joined(separator: "\n")
    }

    private func buildSystemPrompt(for sender: ChatMessage.Sender, isFirstTurn: Bool) -> String {
        guard isFirstTurn else { return "" }

        switch sender {
        case .modelA:
            return "You are Model A in a conversation between two AI models. Use the User Prompt as the starting point for your conversation. You will be discussing topics with Model B, taking turns to respond. Be thoughtful and engaging in your responses. You can use <think></think> tags to show your reasoning process.\n\n"
        case .modelB:
            return "You are Model B in a conversation between two AI models. Model A has just responded to the user's prompt. Continue the discussion by responding thoughtfully to what Model A has said. You can use <think></think> tags to show your reasoning process.\n\n"
        case .user:
            return ""
        }
    }

    private func updateStatus(_ newStatus: String) {
        Task { @MainActor in
            status = newStatus
        }
    }

    // MARK: - Network Communication

    private func generateResponse(
        modelName: String,
        prompt: String,
        port: Int,
        sender: ChatMessage.Sender
    ) async -> String?
    {
        guard !modelName.isEmpty else {
            updateStatus("No model selected for \(sender.displayTitle)")
            return nil
        }

        guard let url = URL(string: "http://127.0.0.1:\(port)/api/generate") else {
            updateStatus("Invalid URL for \(sender.displayTitle)")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300 // 5 minutes timeout

        let payload: [String: Any] = [
            "model": modelName,
            "prompt": prompt,
            "stream": true,
            "options": [
                "temperature": 0.7,
                "top_p": 0.9
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            updateStatus("Failed to encode request for \(sender.displayTitle)")
            return nil
        }

        // Initialize streaming state
        await MainActor.run {
            currentStreamingMessage = ChatMessage(text: "", sender: sender, isThink: false)
            streamingBuffer = ""
        }

        return await withCheckedContinuation { continuation in
            let delegate = StreamingDelegate(
                onChunk: { chunk in
                    Task { @MainActor in
                        self.streamingBuffer += chunk
                    }
                },
                onFinish: {
                    Task { @MainActor in
                        let finalResponse = self.streamingBuffer
                        let (thinkPart, mainPart) = extractThink(text: finalResponse)

                        // Add the final messages to permanent storage
                        if let thinkPart = thinkPart, !thinkPart.isEmpty {
                            self.messages.append(ChatMessage(text: thinkPart, sender: sender, isThink: true))
                        }

                        let finalMainPart = mainPart.isEmpty ? finalResponse : mainPart
                        if !finalMainPart.isEmpty {
                            self.messages.append(ChatMessage(text: finalMainPart, sender: sender, isThink: false))
                        }

                        // Clear streaming state
                        self.resetStreamingState()

                        continuation.resume(returning: finalMainPart)
                    }
                }
            )

            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let task = session.dataTask(with: request)

            Task { @MainActor in
                self.currentStreamingTask = task
            }

            task.resume()
        }
    }
}

// MARK: - Message Bubble Component

struct MessageBubble: View
{
    let message: ChatMessage

    var body: some View
    {
        HStack(alignment: .top, spacing: 12)
        {
            if message.sender == .user
            {
                Spacer(minLength: 50)
                userMessageBubble
            }
            else
            {
                assistantMessageBubble
                Spacer(minLength: 50)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var userMessageBubble: some View
    {
        Text(message.text)
            .textSelection(.enabled)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.accentColor)
            )
            .foregroundColor(.white)
            .font(.body)
    }

    private var assistantMessageBubble: some View
    {
        VStack(alignment: .leading, spacing: 8)
        {
            // Header with model name and thinking indicator
            HStack(spacing: 6)
            {
                Text(message.sender.displayTitle)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                if message.isThink
                {
                    Image(systemName: "brain.head.profile")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }

                Spacer()
            }

            // Message content
            Text(message.text)
                .textSelection(.enabled)
                .font(.body)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(backgroundColorForMessage)
                .stroke(strokeColorForMessage, lineWidth: strokeWidthForMessage)
        )
    }

    private var backgroundColorForMessage: Color
    {
        if message.isThink {
            return Color.yellow.opacity(0.15)
        }

        switch message.sender {
        case .user:
            return Color.accentColor
        case .modelA:
            return Color.green.opacity(0.1)
        case .modelB:
            return Color.orange.opacity(0.1)
        }
    }

    private var strokeColorForMessage: Color
    {
        if message.isThink
        {
            return Color.yellow.opacity(0.4)
        }
        return Color.clear
    }

    private var strokeWidthForMessage: CGFloat
    {
        message.isThink ? 1.0 : 0.8
    }
}
