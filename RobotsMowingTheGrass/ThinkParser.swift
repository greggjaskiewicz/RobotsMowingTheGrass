//
//  ThinkParser.swift
//  RobotsMowingTheGrass
//
//  Created by Gregg Jaskiewicz on 12/06/2025.
//

import Foundation

func extractThink(text: String) -> (String?, String) {
    if let start = text.range(of: "<think>") {
        if let end = text.range(of: "</think>") {
            let mainMessage = String(text[end.upperBound..<text.endIndex])
            if let _ = mainMessage.range(of: "</think>") {
                print("wtf")
            }
            return (nil, mainMessage.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            // Handle incomplete think tag during streaming
            let think = String(text[start.upperBound..<text.endIndex])
            let lastLine = think.components(separatedBy: .newlines).last?.trimmingCharacters(in: .whitespaces) ?? ""
            return ("🤔 " + lastLine, "")
        }
    }
    return (nil, text)
}

// Additional helper for streaming scenarios
func extractThinkStreaming(text: String) -> (thinkPart: String?, mainPart: String, isThinkComplete: Bool) {
    if let start = text.range(of: "<think>") {
        if let end = text.range(of: "</think>") {
            let mainMessage = String(text[end.upperBound..<text.endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (nil, mainMessage, true)
        } else {
            // Think tag is not complete yet
            let think = String(text[start.upperBound..<text.endIndex])
            let lastLine = think.components(separatedBy: .newlines).last?.trimmingCharacters(in: .whitespaces) ?? ""

            return ("🤔 " + lastLine, "", false)
        }
    }
    return (nil, text, true)
}
