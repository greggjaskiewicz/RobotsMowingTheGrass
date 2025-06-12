//
//  ContentView.swift
//  MowingTheGrass
//
//  Created by Gregg Jaskiewicz on 12/06/2025.
//

import SwiftUI

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
    @State private var messages: [ChatMessage] = []
    @State private var userInput: String = ""
    @State private var isProcessing = false
    @State private var status: String = ""

    // Conversation settings
    let maxTurns = 6  // Total exchanges (A->B->A->B...)
    let modelA = "deepseek-r1" //"llama3"
    let portA = 11434
    let modelB = "deepseek-r1" //"phi3"
    let portB = 11435

    var body: some View {
        VStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { message in
                            messageBubble(message)
                        }
                    }
                    .padding()
                }
                .background(Color(NSColor.windowBackgroundColor))
                .onChange(of: messages.count) { _ in
                    if let last = messages.last {
                        scrollProxy.scrollTo(last.id, anchor: .bottom)
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
        }
        .frame(minWidth: 500, minHeight: 600)
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
        Task {
            await runDialogueLoop(firstPrompt: prompt)
            isProcessing = false
            status = ""
        }
    }

    func runDialogueLoop(firstPrompt: String) async {
        var current = firstPrompt
        var lastSender: ChatMessage.Sender = .user

        for turn in 1...maxTurns {
            if lastSender == .user || lastSender == .modelB {
                // Model A's turn
                await MainActor.run { status = "Waiting for Model A…" }
                if let responseA = await generateWithOllama(modelName: modelA, prompt: current, port: portA) {
                    let (thinkA, mainA) = extractThink(text: responseA)
                    if let thinkA = thinkA {
                        await MainActor.run { messages.append(.init(text: thinkA, sender: .modelA, isThink: true)) }
                    }
                    await MainActor.run { messages.append(.init(text: mainA, sender: .modelA, isThink: false)) }
                    current = mainA
                    lastSender = .modelA
                } else {
                    await MainActor.run { status = "Model A error!" }
                    break
                }
            } else {
                // Model B's turn
                await MainActor.run { status = "Waiting for Model B…" }
                if let responseB = await generateWithOllama(modelName: modelB, prompt: current, port: portB) {
                    let (thinkB, mainB) = extractThink(text: responseB)
                    if let thinkB = thinkB {
                        await MainActor.run { messages.append(.init(text: thinkB, sender: .modelB, isThink: true)) }
                    }
                    await MainActor.run { messages.append(.init(text: mainB, sender: .modelB, isThink: false)) }
                    current = mainB
                    lastSender = .modelB
                } else {
                    await MainActor.run { status = "Model B error!" }
                    break
                }
            }
        }
        await MainActor.run { status = "" }
    }
}
