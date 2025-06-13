//
//  ExportDocument.swift
//  RobotsMowingTheGrass
//
//  Created by Gregg Jaskiewicz on 12/06/2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct ExportChatDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText] }

    private let chatData: ChatExportData

    init(messages: [ChatMessage]) {
        self.chatData = ChatExportData(messages: messages)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        if let jsonString = String(data: data, encoding: .utf8),
           let exportData = try? JSONDecoder().decode(ChatExportData.self, from: data) {
            self.chatData = exportData
        } else {
            // Fallback for plain text
            let textContent = String(data: data, encoding: .utf8) ?? ""
            self.chatData = ChatExportData(plainText: textContent)
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data: Data

        if configuration.contentType == .json {
            data = try JSONEncoder().encode(chatData)
        } else {
            data = chatData.toPlainText().data(using: .utf8) ?? Data()
        }

        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Export Data Structure

private struct ChatExportData: Codable {
    let version: String
    let exportDate: Date
    let messages: [ExportMessage]
    let metadata: ExportMetadata

    init(messages: [ChatMessage]) {
        self.version = "1.0"
        self.exportDate = Date()
        self.messages = messages.map(ExportMessage.init)
        self.metadata = ExportMetadata(
            totalMessages: messages.count,
            userMessages: messages.filter { $0.sender == .user }.count,
            modelAMessages: messages.filter { $0.sender == .modelA }.count,
            modelBMessages: messages.filter { $0.sender == .modelB }.count,
            thinkingMessages: messages.filter { $0.isThink }.count
        )
    }

    init(plainText: String) {
        self.version = "1.0"
        self.exportDate = Date()
        self.messages = []
        self.metadata = ExportMetadata(
            totalMessages: 0,
            userMessages: 0,
            modelAMessages: 0,
            modelBMessages: 0,
            thinkingMessages: 0
        )
    }

    func toPlainText() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        var output = [
            "Chat Export",
            "Generated: \(formatter.string(from: exportDate))",
            "Total Messages: \(metadata.totalMessages)",
            String(repeating: "=", count: 50),
            ""
        ]

        for (index, message) in messages.enumerated() {
            let turnNumber = index + 1
            let sender = message.sender.displayName
            let prefix = message.isThink ? "[Thinking] " : ""

            output.append("Turn \(turnNumber): \(sender)")
            output.append("\(prefix)\(message.text)")
            output.append("")
        }

        return output.joined(separator: "\n")
    }
}

private struct ExportMessage: Codable {
    let text: String
    let sender: ExportSender
    let isThink: Bool
    let timestamp: Date

    init(from message: ChatMessage) {
        self.text = message.text
        self.sender = ExportSender(from: message.sender)
        self.isThink = message.isThink
        self.timestamp = Date() // Current timestamp as we don't store original timestamps
    }
}

private struct ExportMetadata: Codable {
    let totalMessages: Int
    let userMessages: Int
    let modelAMessages: Int
    let modelBMessages: Int
    let thinkingMessages: Int
}

private enum ExportSender: String, Codable {
    case user = "user"
    case modelA = "model_a"
    case modelB = "model_b"

    init(from sender: ChatMessage.Sender) {
        switch sender {
        case .user: self = .user
        case .modelA: self = .modelA
        case .modelB: self = .modelB
        }
    }

    var displayName: String {
        switch self {
        case .user: return "User"
        case .modelA: return "Model A"
        case .modelB: return "Model B"
        }
    }
}
