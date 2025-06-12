//
//  OllamaAPI.swift
//  MowingTheGrass
//
//  Created by Gregg Jaskiewicz on 12/06/2025.
//

import Foundation

func parseNDJSONResponse(_ data: Data) -> String
{
    guard let dataString = String(data: data, encoding: .utf8) else { return "" }
    let lines = dataString.split(separator: "\n")
    var response = ""
    for line in lines {
        guard let jsonData = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let chunk = obj["response"] as? String
        else { continue }
        response += chunk
    }
    return response
}

func generateWithOllama(modelName: String, prompt: String, port: Int) async -> String? {
    guard let url = URL(string: "http://127.0.0.1:\(port)/api/generate") else { return nil }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    let payload: [String: Any] = [
        "model": modelName,
        "prompt": prompt
    ]
    request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        let fullResponse = parseNDJSONResponse(data)
        return fullResponse
    } catch {
        print("Ollama error: \(error)")
    }
    return nil
}
