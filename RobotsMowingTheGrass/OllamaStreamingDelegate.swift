//
//  OllamaStreamingDelegate.swift
//  RobotsMowingTheGrass
//
//  Created by Gregg Jaskiewicz on 12/06/2025.
//

import Foundation

/// Handles streaming responses from Ollama API
class StreamingDelegate: NSObject, URLSessionDataDelegate {
    private let onChunk: (String) -> Void
    private let onFinish: () -> Void
    private var buffer = Data()

    /// Initialize the streaming delegate
    /// - Parameters:
    ///   - onChunk: Called when a new chunk of text is received
    ///   - onFinish: Called when the stream is complete or cancelled
    init(onChunk: @escaping (String) -> Void, onFinish: @escaping () -> Void) {
        self.onChunk = onChunk
        self.onFinish = onFinish
        super.init()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)

        // Process complete lines (separated by newlines)
        while let newlineRange = buffer.range(of: Data([0x0A])) { // \n
            let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
            buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

            processLine(data: lineData)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Process any remaining data in buffer
        if !buffer.isEmpty {
            processLine(data: buffer)
            buffer.removeAll()
        }

        // Always call onFinish, whether completed successfully or with error
        onFinish()

        if let error = error {
            // Only log if it's not a cancellation error
            if (error as NSError).code != NSURLErrorCancelled {
                print("Streaming error: \(error.localizedDescription)")
            }
        }
    }

    private func processLine(data: Data) {
        guard let lineString = String(data: data, encoding: .utf8),
              !lineString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        do {
            guard let jsonData = lineString.data(using: .utf8),
                  let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                return
            }

            // Extract the response chunk
            if let chunk = jsonObject["response"] as? String {
                onChunk(chunk)
            }

            // Check if this is the final chunk
            if let done = jsonObject["done"] as? Bool, done {
                // This was the final chunk, but we'll let didCompleteWithError handle the finish
                return
            }

        } catch {
            // Invalid JSON - skip this line
            print("Failed to parse JSON line: \(error.localizedDescription)")
        }
    }
}
