//
//  ContentView.swift
//  RobotsMowingTheGrass
//
//  Created by Gregg Jaskiewicz on 12/06/2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let sender: Sender
    let isThink: Bool

    enum Sender {
        case user, modelA, modelB
    }
}

struct ContentView: View {
    @AppStorage("portA") var portA: Int = 11434
    @AppStorage("portB") var portB: Int = 11435
    @AppStorage("selectedModelA") var selectedModelA: String = ""
    @AppStorage("selectedModelB") var selectedModelB: String = ""
    @AppStorage("maxTurns") var maxTurns: Int = 8
    @AppStorage("infiniteTurns") var infinite: Bool = false

    @State private var messages: [ChatMessage] = []
    @State private var userInput: String = ""
    @State private var isProcessing = false
    @State private var status: String = ""

    @State private var isSaving = false
    @State private var turnNumber = 0 // Track the current turn

    @State private var currentChatTask: Task<Void, Never>? = nil

    // For streaming support
    @State private var currentStreamingMessage: ChatMessage?
    @State private var streamingBuffer: String = ""

    var body: some View {
            NavigationSplitView {
                SettingsPanel(
                    portA: $portA,
                    portB: $portB,
                    selectedModelA: $selectedModelA,
                    selectedModelB: $selectedModelB,
                    maxTurns: $maxTurns,
                    infinite: $infinite
                )
            } detail: {
                VStack
                {
                    // Status bar at the top or bottom:
                            HStack {
                                Text("Turn: \(turnNumber)")
                                Spacer()
                                Button("Save As") { isSaving = true }
                                Button("Clear") {
                                    messages.removeAll()
                                    turnNumber = 0
                                    currentStreamingMessage = nil
                                    streamingBuffer = ""
                                }
                                Button("Cancel") {
                                    currentChatTask?.cancel()
                                    isProcessing = false
                                    status = "Cancelled by user"
                                    currentChatTask = nil
                                    currentStreamingMessage = nil
                                    streamingBuffer = ""
                                }
                                .disabled(currentChatTask == nil)
                            }.padding([.top, .horizontal])
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(displayMessages) { message in
                                    messageBubble(message)
                                }
                            }
                            .padding()
                        }
                        .background(Color(NSColor.windowBackgroundColor))
                        .onChange(of: displayMessages.count) { _ in
                            if let last = displayMessages.last {
                                scrollProxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                        .onChange(of: streamingBuffer) { _ in
                            if let current = currentStreamingMessage {
                                scrollProxy.scrollTo(current.id, anchor: .bottom)
                            }
                        }
                    }
                    if isProcessing || !status.isEmpty {
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.vertical, 4)
                    }
                    Divider()
                    HStack {
                        TextField("Type your message…", text: $userInput)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onSubmit(sendUserMessage)
                        Button("Send") {
                            sendUserMessage()
                        }
                        .disabled(userInput.isEmpty || isProcessing)
                    }
                    .padding()
                }.fileExporter(
                    isPresented: $isSaving,
                    document: ExportChatDocument(messages: messages),
                    contentType: .json,
                    defaultFilename: "LlamasChat"
                ) { result in
                    // Optionally handle success/failure here
                }
            }
        .frame(minWidth: 500, minHeight: 600)
    }

    // Computed property to combine permanent messages with streaming message
    private var displayMessages: [ChatMessage] {
        var result = messages
        if let streaming = currentStreamingMessage {
            let (thinkPart, mainPart) = extractThink(text: streamingBuffer)

            if let thinkPart = thinkPart, !thinkPart.isEmpty {
                let thinkMessage = ChatMessage(
                    text: thinkPart,
                    sender: streaming.sender,
                    isThink: true
                )
                result.append(thinkMessage)
            }

            if !mainPart.isEmpty {
                let mainMessage = ChatMessage(
                    text: mainPart,
                    sender: streaming.sender,
                    isThink: false
                )
                result.append(mainMessage)
            } else if thinkPart == nil && !streamingBuffer.isEmpty {
                // No think tags, just show the streaming content
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

    @ViewBuilder
    func messageBubble(_ message: ChatMessage) -> some View {
        HStack(alignment: .bottom) {
            if message.sender == .user {
                Spacer()
                Text(message.text)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            } else if message.isThink {
                Text(message.text)
                    .padding()
                    .background(Color.yellow.opacity(0.7))
                    .foregroundColor(.black)
                    .cornerRadius(12)
                Spacer()
            } else if message.sender == .modelA {
                Text("Model A:\n\(message.text)")
                    .padding()
                    .background(Color.green.opacity(0.8))
                    .foregroundColor(.black)
                    .cornerRadius(12)
                Spacer()
            } else {
                Text("Model B:\n\(message.text)")
                    .padding()
                    .background(Color.orange.opacity(0.8))
                    .foregroundColor(.black)
                    .cornerRadius(12)
                Spacer()
            }
        }
        .id(message.id)
        .padding(.horizontal)
    }

    func sendUserMessage() {
        guard !userInput.isEmpty else { return }
        let prompt = userInput
        userInput = ""
        messages.append(.init(text: prompt, sender: .user, isThink: false))
        isProcessing = true
        status = "Waiting for Model A…"
        currentChatTask = Task {
            await runDialogueLoop(firstPrompt: prompt)
            isProcessing = false
            status = ""
        }
    }

    let contextTurns = 12  // Or make this user-configurable

    func runDialogueLoop(firstPrompt: String) async
    {
        var current = firstPrompt
        var lastSender: ChatMessage.Sender = .user
        let turnLimit = infinite ? Int.max : maxTurns

        while turnNumber < turnLimit {
            turnNumber += 1

            let contextMessages = messages.suffix(contextTurns)
            let historyString = contextMessages.map { m in
                let who = m.sender == .user ? "User"
                : m.sender == .modelA ? "Model A"
                : "Model B"
                return "\(who): \(m.text)"
            }.joined(separator: "\n")

            if Task.isCancelled { break }

            if lastSender == .user || lastSender == .modelB {
                // Model A's turn
                await MainActor.run { status = "Waiting for Model A…" }
                let promptForModelA = historyString + "\nModel A:"

                if let responseA = await generateWithOllamaStreaming(
                    modelName: selectedModelA,
                    prompt: promptForModelA,
                    port: portA,
                    sender: .modelA
                ) {
                    current = responseA
                    lastSender = .modelA
                } else {
                    await MainActor.run { status = "Model A error!" }
                    break
                }
            } else {
                var promptForModelB = current
                if turnNumber == 2 {
                    // lets tell this guy what initial prompt is
                    promptForModelB = firstPrompt + "\n what is your response? :" + current
                }

                // Model B's turn
                await MainActor.run { status = "Waiting for Model B…" }
                let fullPromptForModelB = historyString + "\nModel B:"

                if let responseB = await generateWithOllamaStreaming(
                    modelName: selectedModelB,
                    prompt: fullPromptForModelB,
                    port: portB,
                    sender: .modelB
                ) {
                    current = responseB
                    lastSender = .modelB
                } else {
                    await MainActor.run { status = "Model B error!" }
                    break
                }
            }
        }
        await MainActor.run { status = "" }
    }

    func generateWithOllamaStreaming(modelName: String, prompt: String, port: Int, sender: ChatMessage.Sender) async -> String? {
        guard let url = URL(string: "http://127.0.0.1:\(port)/api/generate") else { return nil }
        if let _ = prompt.range(of: "</think>") {
            print("wtf")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let payload: [String: Any] = [
            "model": modelName,
            "prompt": prompt,
            "stream": true
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Initialize streaming state
        await MainActor.run {
            currentStreamingMessage = ChatMessage(text: "", sender: sender, isThink: false)
            streamingBuffer = ""
        }

        return await withCheckedContinuation { continuation in
            let delegate = StreamingDelegate { chunk in
                Task { @MainActor in
                    self.streamingBuffer += chunk
                }
            } onFinish: {
                Task { @MainActor in
//                    guard let self = self else {
//                        continuation.resume(returning: nil)
//                        return
//                    }

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
                    self.currentStreamingMessage = nil
                    self.streamingBuffer = ""

                    continuation.resume(returning: finalMainPart)
                }
            }

            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let task = session.dataTask(with: request)
            task.resume()
        }
    }
}
