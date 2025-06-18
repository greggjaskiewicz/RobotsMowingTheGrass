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

        if let _ = String(data: data, encoding: .utf8),
           let exportData = try? JSONDecoder().decode(ChatExportData.self, from: data) {
            self.chatData = exportData
        } else {
            // Fallback for plain text
            let textContent = String(data: data, encoding: .utf8) ?? ""
            self.chatData = ChatExportData(plainText: textContent)
        }
    }

    static var writableContentTypes: [UTType] {
        [.json, .plainText, .html]
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data: Data

        switch configuration.contentType {
        case .json:
            data = try JSONEncoder().encode(chatData)

        case .plainText:
            data = chatData.toPlainText().data(using: .utf8) ?? Data()

        case .html:
            data = htmlRepresentation.data(using: .utf8) ?? Data()

        default:
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSDebugDescriptionErrorKey: "Unsupported content type \(configuration.contentType)"
            ])
        }

        return FileWrapper(regularFileWithContents: data)
    }

//    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
//        let data: Data
//
//        if configuration.contentType == .json {
//            data = try JSONEncoder().encode(chatData)
//        } else {
//            data = chatData.toPlainText().data(using: .utf8) ?? Data()
//        }
//
//        return FileWrapper(regularFileWithContents: data)
//    }

    func exportAsHTML(to url: URL) throws {
        try htmlRepresentation.write(to: url, atomically: true, encoding: .utf8)
    }

    var htmlRepresentation: String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <style>
                body {
                    font-family: -apple-system, Helvetica, sans-serif;
                    background: #f9f9f9;
                    padding: 2em;
                    line-height: 1.6;
                }
                .bubble {
                    padding: 1em;
                    margin-bottom: 1.2em;
                    border-radius: 10px;
                    max-width: 600px;
                    box-shadow: 0 1px 3px rgba(0,0,0,0.1);
                }
                .user {
                    background: #d0ebff;
                    align-self: flex-end;
                }
                .model {
                    background: #e9ecef;
                }
                .sender {
                    font-weight: bold;
                    font-size: 0.9em;
                    margin-bottom: 0.4em;
                    color: #495057;
                }
            </style>
        </head>
        <body>
        \(chatData.messages.map { message in
            """
            <div class="bubble \(message.isUser ? "user" : "model")">
                <div class="sender">\(escapeHTML(message.senderName.isEmpty ? "User" : message.senderName))</div>
                <div class="content">\(escapeHTML(message.text).replacingOccurrences(of: "\n", with: "<br>"))</div>
            </div>
            """
        }.joined(separator: "\n"))
        </body>
        </html>
        """
    }

    private func escapeHTML(_ input: String) -> String {
        input
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

// MARK: - Export Data Structure

private struct ChatExportData: Codable {
    let version: String
    let exportDate: Date
    let messages: [ExportMessage]
    let metadata: ExportMetadata

    init(messages: [ChatMessage]) {
        self.version = "2.0" // Updated version for new format
        self.exportDate = Date()
        self.messages = messages.map(ExportMessage.init)

        // Count messages by sender
        var senderCounts: [String: Int] = ["user": 0]
        var thinkingCount = 0

        for message in messages {
            if message.isUser {
                senderCounts["user", default: 0] += 1
            } else {
                senderCounts[message.senderName, default: 0] += 1
            }
            if message.isThink {
                thinkingCount += 1
            }
        }

        self.metadata = ExportMetadata(
            totalMessages: messages.count,
            senderCounts: senderCounts,
            thinkingMessages: thinkingCount
        )
    }

    init(plainText: String) {
        self.version = "2.0"
        self.exportDate = Date()
        self.messages = []
        self.metadata = ExportMetadata(
            totalMessages: 0,
            senderCounts: [:],
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
            ""
        ]

        // Add sender statistics
        output.append("Participants:")
        for (sender, count) in metadata.senderCounts.sorted(by: { $0.key < $1.key }) {
            output.append("  \(sender): \(count) messages")
        }
        output.append("  Thinking messages: \(metadata.thinkingMessages)")

        output.append(String(repeating: "=", count: 50))
        output.append("")

        for (index, message) in messages.enumerated() {
            let turnNumber = index + 1
            let prefix = message.isThink ? "[Thinking] " : ""

            output.append("Turn \(turnNumber): \(message.senderName)")
            output.append("\(prefix)\(message.text)")
            output.append("")
        }

        return output.joined(separator: "\n")
    }
}

private struct ExportMessage: Codable {
    let text: String
    let senderID: String
    let senderName: String
    let isThink: Bool
    let isUser: Bool
    let timestamp: Date

    init(from message: ChatMessage) {
        self.text = message.text
        self.senderID = message.senderID.uuidString
        self.senderName = message.senderName
        self.isThink = message.isThink
        self.isUser = message.isUser
        self.timestamp = Date() // Current timestamp as we don't store original timestamps
    }
}

private struct ExportMetadata: Codable {
    let totalMessages: Int
    let senderCounts: [String: Int]
    let thinkingMessages: Int
}
