//
//  FileExporterHelper.swift
//  RobotsMowingTheGrass
//
//  Created by Gregg Jaskiewicz on 29/06/2025.
//

import AppKit
import UniformTypeIdentifiers

class FileExporterHelper {

    enum ExportFormat: String, CaseIterable {
        case json = "JSON"
        case plainText = "Plain Text"
        case html = "HTML"

        var utType: UTType {
            switch self {
            case .json: return .json
            case .plainText: return .plainText
            case .html: return .html
            }
        }

        var fileExtension: String {
            switch self {
            case .json: return "json"
            case .plainText: return "txt"
            case .html: return "html"
            }
        }
    }

    // Helper class to handle popup events
    private class SavePanelDelegate: NSObject {
        var selectedFormat: ExportFormat = .json
        weak var panel: NSSavePanel?

        @objc func formatChanged(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            if index >= 0 && index < ExportFormat.allCases.count {
                selectedFormat = ExportFormat.allCases[index]
                panel?.allowedContentTypes = [selectedFormat.utType]

                // Update filename extension
                if let panel = panel {
                    let currentName = panel.nameFieldStringValue
                    let nameWithoutExt = (currentName as NSString).deletingPathExtension
                    panel.nameFieldStringValue = "\(nameWithoutExt).\(selectedFormat.fileExtension)"
                }
            }
        }
    }

    static func save(messages: [ChatMessage], defaultFilename: String = "ChatExport")
    {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(defaultFilename).json"
        panel.canCreateDirectories = true

        let delegate = SavePanelDelegate()
        delegate.panel = panel

        // Create accessory view with format selector
        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 30))

        let label = NSTextField(labelWithString: "Format:")
        label.frame = NSRect(x: 0, y: 5, width: 60, height: 20)
        accessoryView.addSubview(label)

        let popup = NSPopUpButton(frame: NSRect(x: 70, y: 0, width: 200, height: 30))
        ExportFormat.allCases.forEach { format in
            popup.addItem(withTitle: format.rawValue)
        }
        popup.selectItem(at: 0) // Default to first item (JSON)

        popup.target = delegate
        popup.action = #selector(SavePanelDelegate.formatChanged(_:))

        accessoryView.addSubview(popup)
        panel.accessoryView = accessoryView

        // Set initial allowed content type
        panel.allowedContentTypes = [delegate.selectedFormat.utType]
        panel.allowsOtherFileTypes = false

        // Keep delegate alive during panel presentation
        objc_setAssociatedObject(panel, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            let data: Data?

            switch delegate.selectedFormat {
            case .json:
                data = try? JSONEncoder().encode(messages)

            case .plainText:
                let plainText = ExportChatDocument(messages: messages).exportAsText() ?? ""
                data = plainText.data(using: .utf8)

            case .html:
                let exportDocument = ExportChatDocument(messages: messages)
                data = exportDocument.htmlRepresentation.data(using: .utf8)
            }

            if let data = data {
                do {
                    try data.write(to: url)
                    print("Saved to: \(url)")
                } catch {
                    print("Save failed: \(error)")
                }
            }
        }
    }
}
