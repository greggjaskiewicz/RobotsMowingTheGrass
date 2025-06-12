//
//  ThinkParser.swift
//  RobotsMowingTheGrass
//
//  Created by Gregg Jaskiewicz on 12/06/2025.
//

import Foundation

func extractThink(text: String) -> (String?, String) {
    // Returns (thinkText, mainMessage)
    if let start = text.range(of: "<think>"),
       let end = text.range(of: "</think>") {
        let think = String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        var mainMessage = text
        mainMessage.removeSubrange(start.lowerBound...end.upperBound)
        return ("🤔 " + think, mainMessage.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return (nil, text)
}
