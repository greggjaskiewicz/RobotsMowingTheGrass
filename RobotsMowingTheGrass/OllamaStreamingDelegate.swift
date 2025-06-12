//
//  OllamaStreamingDelegate.swift
//  RobotsMowingTheGrass
//
//  Created by Gregg Jaskiewicz on 12/06/2025.
//

import Foundation
import Combine

// MARK: - Robot's Streaming Delegate

class StreamingDelegate: NSObject, URLSessionDataDelegate
{
    private let onChunk: (String) -> Void
    private let onFinish: () -> Void
    private var buffer = Data()

    init(onChunk: @escaping (String) -> Void, onFinish: @escaping () -> Void)
    {
        self.onChunk = onChunk
        self.onFinish = onFinish
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data)
    {
        buffer.append(data)
        while let range = buffer.range(of: Data([0x0A])) // newline = \n
        {
            let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex...range.lowerBound)
            if let lineString = String(data: lineData, encoding: .utf8),
               let jsonData = lineString.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let chunk = obj["response"] as? String
            {
                onChunk(chunk)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?)
    {
        onFinish()
    }
}
