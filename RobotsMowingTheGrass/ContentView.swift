//
//  ContentView.swift
//  RobotsMowingTheGrass
//
//  Created by Gregg Jaskiewicz on 12/06/2025.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

struct ContentView: View {
    @AppStorage("maxTurns") private var maxTurns: Int = 8
    @AppStorage("infiniteTurns") private var infinite: Bool = false
    @AppStorage("contextTurns") private var contextTurns: Int = 12

    @StateObject private var configManager = ModelConfigurationManager()
    @State private var userInput: String = ""
    @State private var isSaving = false

    var body: some View {
        ContentViewBody(
            configManager: configManager,
            maxTurns: $maxTurns,
            infinite: $infinite,
            contextTurns: $contextTurns,
            userInput: $userInput,
            isSaving: $isSaving
        )
    }
}

struct ContentViewBody: View {
    let configManager: ModelConfigurationManager
    @Binding var maxTurns: Int
    @Binding var infinite: Bool
    @Binding var contextTurns: Int
    @Binding var userInput: String
    @Binding var isSaving: Bool
    @State private var selectedExportFormat: UTType = .json

    @StateObject private var viewModel: ChatViewModel

    init(
        configManager: ModelConfigurationManager,
        maxTurns: Binding<Int>,
        infinite: Binding<Bool>,
        contextTurns: Binding<Int>,
        userInput: Binding<String>,
        isSaving: Binding<Bool>
    ) {
        self.configManager = configManager
        self._maxTurns = maxTurns
        self._infinite = infinite
        self._contextTurns = contextTurns
        self._userInput = userInput
        self._isSaving = isSaving
        self._viewModel = StateObject(wrappedValue: ChatViewModel(configManager: configManager))
    }

    var body: some View {
        NavigationSplitView {
            ModelSettingsPanel(
                maxTurns: $maxTurns,
                infinite: $infinite,
                contextTurns: $contextTurns
            )
            .environmentObject(configManager)
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
                document: ExportChatDocument(messages: viewModel.messages),
                contentType: selectedExportFormat,
                defaultFilename: "LlamasChat"
            ) { result in
                handleExportResult(result)
            }
        }
        .frame(minWidth: 700, minHeight: 600)
    }

    private var controlBar: some View {
        HStack {
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
            Picker("", selection: $selectedExportFormat) {
                Text("JSON").tag(UTType.json)
                Text("Txt").tag(UTType.plainText)
                Text("HTML").tag(UTType.html)
            }
            .pickerStyle(.segmented)
            .padding()
            Spacer()
            Button("Save As") {
                isSaving = true
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

    private var messagesList: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.displayMessages) { message in
                        MessageBubble(
                            message: message,
                            bubbleColor: viewModel.bubbleColor(for: message)
                        )
                    }
                }
                .padding()
            }
            .background(Color(NSColor.windowBackgroundColor))
            .onChange(of: viewModel.displayMessages.count) {
                scrollToBottom(scrollProxy)
            }
        }
    }

    private var statusBar: some View {
        Group {
            if viewModel.isProcessing || !viewModel.status.isEmpty {
                HStack {
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

    private var inputSection: some View {
        HStack {
            TextField("Type your message…", text: $userInput, axis: .vertical)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .disabled(viewModel.isProcessing)
                .onSubmit(sendUserMessage)
                .lineLimit(1...5)

            Button("Send") {
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
