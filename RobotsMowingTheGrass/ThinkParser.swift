//
//  ThinkParser.swift
//  RobotsMowingTheGrass
//
//  Created by Gregg Jaskiewicz on 12/06/2025.
//

import Foundation

/// Extracts thinking content from model responses that use <think></think> tags
/// - Parameter text: The raw response text that may contain think tags
/// - Returns: A tuple containing the thinking content (if any) and the main response content
func extractThink(text: String) -> (String?, String)
{
    guard let thinkStart = text.range(of: "<think>") else {
        // No think tags found, return the entire text as main content
        return (nil, text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    if let thinkEnd = text.range(of: "</think>")
    {
        // Complete think tags found
        let thinkContent = String(text[thinkStart.upperBound..<thinkEnd.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let mainContent = String(text[thinkEnd.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate that we don't have nested or malformed think tags
        if mainContent.contains("</think>")
        {
            print("Warning: Found malformed think tags in response")
            // Return the entire text as main content if tags are malformed
            return (nil, text.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return (thinkContent.isEmpty ? nil : thinkContent, mainContent)
    }
    else
    {
        // Incomplete think tag (streaming scenario)
        let thinkContent = String(text[thinkStart.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // For streaming, we'll show the last line of thinking with a thinking indicator
        let lastLine = thinkContent.components(separatedBy: .newlines)
            .last?
            .trimmingCharacters(in: .whitespaces) ?? ""

        return (lastLine.isEmpty ? nil : "🤔 " + lastLine, "")
    }
}

/// Extracts thinking content for streaming scenarios with more detailed state information
/// - Parameter text: The raw response text that may contain think tags
/// - Returns: A tuple containing the thinking content, main content, and completion status
func extractThinkStreaming(text: String) -> (thinkPart: String?, mainPart: String, isThinkComplete: Bool)
{
    guard let thinkStart = text.range(of: "<think>") else {
        // No think tags found
        return (nil, text.trimmingCharacters(in: .whitespacesAndNewlines), true)
    }

    if let thinkEnd = text.range(of: "</think>")
    {
        // Think tags are complete
        let thinkContent = String(text[thinkStart.upperBound..<thinkEnd.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let mainContent = String(text[thinkEnd.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (thinkContent.isEmpty ? nil : thinkContent, mainContent, true)
    }
    else
    {
        // Think tags are incomplete (still streaming)
        let thinkContent = String(text[thinkStart.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let lastLine = thinkContent.components(separatedBy: .newlines)
            .last?
            .trimmingCharacters(in: .whitespaces) ?? ""

        let displayThink = lastLine.isEmpty ? nil : "🤔 " + lastLine

        return (displayThink, "", false)
    }
}
