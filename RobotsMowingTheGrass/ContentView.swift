//
//  ContentView.swift
//  RobotsMowingTheGrass
//
//  Created by Gregg Jaskiewicz on 12/06/2025.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

struct ContentView: View
{
    @AppStorage("maxTurns") private var maxTurns: Int = 8
    @AppStorage("infiniteTurns") private var infinite: Bool = false
    @AppStorage("contextTurns") private var contextTurns: Int = 12

    @StateObject private var configManager = ModelConfigurationManager()
    @State private var userInput: String = ""

    var body: some View
    {
        ContentViewBody(
            configManager: configManager,
            maxTurns: $maxTurns,
            infinite: $infinite,
            contextTurns: $contextTurns,
            userInput: $userInput,
        )
    }
}

struct ContentViewBody: View
{
    let configManager: ModelConfigurationManager
    @Binding var maxTurns: Int
    @Binding var infinite: Bool
    @Binding var contextTurns: Int
    @Binding var userInput: String

    @StateObject private var viewModel: ChatViewModel
    @State private var clarificationResponse: String = ""
    @State private var showingSettings = false

    init(
        configManager: ModelConfigurationManager,
        maxTurns: Binding<Int>,
        infinite: Binding<Bool>,
        contextTurns: Binding<Int>,
        userInput: Binding<String>
    )
    {
        self.configManager = configManager
        self._maxTurns = maxTurns
        self._infinite = infinite
        self._contextTurns = contextTurns
        self._userInput = userInput
        self._viewModel = StateObject(wrappedValue: ChatViewModel(configManager: configManager))
    }

    var body: some View
    {
            VStack(spacing: 0)
        {
                controlBar
                messagesList
                statusBar
                Divider()
                inputSection
            }
            .sheet(isPresented: $viewModel.isClarificationPresented)
        {
                        VStack(spacing: 20) {
                            Text(viewModel.pendingClarificationPrompt ?? "Need your input:")
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .padding()

                            TextField("Type your response here…", text: $clarificationResponse)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .padding(.horizontal)

                            HStack {
                                Spacer()
                                Button("Cancel") {
                                    viewModel.isClarificationPresented = false
                                    clarificationResponse = ""
                                }
                                Button("Submit") {
                                    // resume the continuation in the ViewModel
                                    viewModel.clarificationContinuation?.resume(returning: clarificationResponse)
                                    clarificationResponse = ""
                                }
                                .keyboardShortcut(.defaultAction)
                            }
                            .padding()
                        }
                        .frame(width: 400, height: 200)
                    }
            .sheet(isPresented: $showingSettings) {
                VStack {
                   HStack {
                       Spacer()
                       Button("Done") {
                           showingSettings = false
                       }
                       .keyboardShortcut(.cancelAction)
                   }
                   .padding()

                    ModelSettingsPanel(
                        maxTurns: $maxTurns,
                        infinite: $infinite,
                        contextTurns: $contextTurns
                    )
                    .environmentObject(configManager)
               }
                .frame(width: 500, height: 600)
            }
    }

    private var controlBar: some View {
        HStack {
            Button(action: { showingSettings = true }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2)  // or .title, .largeTitle
            }
            .buttonStyle(PlainButtonStyle())
                        Text("Turn: \(viewModel.turnNumber)")
                .font(.caption)
                .foregroundColor(.secondary)

            if !configManager.enabledConfigurations.isEmpty {
                Text("•")
                    .foregroundColor(.secondary)
                Text("Active: \(configManager.enabledConfigurations.map { $0.displayName }.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Save As…")
            {
                FileExporterHelper.save(messages: viewModel.messages)
            }
            .disabled(viewModel.messages.isEmpty)

            Button("Clear") {
                viewModel.clear()
            }
            .disabled(viewModel.messages.isEmpty && !viewModel.isProcessing)

            Button("Cancel") {
                viewModel.cancel()
            }
            .disabled(!viewModel.isProcessing)
        }
        .padding([.top, .horizontal])
    }

    @State private var hideCompletedThinking = false

    private var messagesList: some View
    {
        VStack(spacing: 0) {
           HStack {
               Toggle("Hide completed thinking", isOn: $hideCompletedThinking)
                   .font(.caption)
               Spacer()
           }
           .padding(.horizontal)
           .padding(.top, 8)

           Divider()

            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                       ForEach(filteredMessages) { message in
                            MessageBubble(
                                message: message,
                                bubbleColor: viewModel.bubbleColor(for: message)
                            )
                        }
                    }
                    .padding()
                }
                .background(Color(NSColor.windowBackgroundColor))
               .onChange(of: filteredMessages.count) {
                    scrollToBottom(scrollProxy)
                }
            }
       }
    }

    private var filteredMessages: [ChatMessage] {
        if hideCompletedThinking {
            return viewModel.displayMessages.filter { message in
                !message.isThink || message.isStreaming
            }
        }
        return viewModel.displayMessages
    }

    private var statusBar: some View
    {
        Group
        {
            if viewModel.isProcessing || !viewModel.status.isEmpty
            {
                HStack
                {
                    if viewModel.isProcessing
                    {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Text(viewModel.status)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                .animation(.easeInOut(duration: 0.2), value: viewModel.status)
            }
        }
    }

    private var inputSection: some View
    {
        HStack(alignment: .bottom)
        {
            ZStack(alignment: .topLeading)
            {
                TextEditor(text: $userInput)
                    .padding(4)
                    .frame(minHeight: 40, maxHeight: 120)
                    .disabled(viewModel.isProcessing)

                if userInput.isEmpty
                {
                    Text("Type your message…")
                        .foregroundColor(.secondary)
                        .padding(.top, 10)      // tweak to align with editor’s text inset
                        .padding(.leading, 8)
                        .allowsHitTesting(false) // so the user can tap into the editor
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                NSApp.keyWindow?.makeFirstResponder(nil)
                            }
                        }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.5))
            )

            Button("Send")
            {
                sendUserMessage()
            }
            .disabled(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isProcessing)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding()
    }

    // MARK: - Actions

    private func sendUserMessage() {
        viewModel.sendUserMessage(userInput)
        userInput = ""
    }

    private func scrollToBottom(_ scrollProxy: ScrollViewProxy) {
        if let last = viewModel.displayMessages.last {
            withAnimation(.easeOut(duration: 0.3)) {
                scrollProxy.scrollTo(last.id, anchor: .bottom)
            }
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
}

// MARK: - Updated Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    let bubbleColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.isUser {
                Spacer(minLength: 50)
                userMessageBubble
            } else {
                assistantMessageBubble
                Spacer(minLength: 50)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .opacity(message.isStreaming ? 0.8 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: message.isStreaming)
    }

    private var userMessageBubble: some View {
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

    private var assistantMessageBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with model name and indicators
            HStack(spacing: 6) {
                Text(message.senderName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                if message.isThink {
                    Image(systemName: "brain.head.profile")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }

                if message.isStreaming {
                    ProgressView()
                        .scaleEffect(0.5)
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

    private var backgroundColorForMessage: Color {
        if message.isThink {
            return bubbleColor.opacity(0.3)
        }
        return bubbleColor
    }

    private var strokeColorForMessage: Color {
        if message.isThink {
            return Color.yellow.opacity(0.4)
        }
        if message.isStreaming {
            return Color.gray.opacity(0.3)
        }
        return Color.clear
    }

    private var strokeWidthForMessage: CGFloat {
        if message.isThink || message.isStreaming {
            return 1.0
        }
        return 0.8
    }
}
