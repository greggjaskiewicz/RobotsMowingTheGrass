//
//  ExportDocument.swift
//  RobotsMowingTheGrass
//
//  Created by Gregg Jaskiewicz on 12/06/2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct ExportChatDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var text: String

    init(messages: [ChatMessage]) {
        // You can customize this for markdown, plain text, etc.
        let enc = messages.enumerated().map { i, m in
            let who = m.sender == .user ? "User"
                    : m.sender == .modelA ? "Model A"
                    : "Model B"
            return "Turn \(i): [\(who)] \(m.isThink ? "<think> " : "")\(m.text)"
        }
        self.text = enc.joined(separator: "\n\n")
    }

    init(configuration: ReadConfiguration) throws {
        self.text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: text.data(using: .utf8) ?? Data())
    }
}
