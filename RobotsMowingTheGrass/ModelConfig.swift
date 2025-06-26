//
//  ModelConfig.swift
//  RobotsMowingTheGrass
//
//  Created by Gregg Jaskiewicz on 13/06/2025.
//

import SwiftUI
import Combine

// MARK: - Array Extension for Safe Access
extension Array
{
    subscript(safe index: Int) -> Element?
    {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Personality Preset Enum

enum PersonalityPreset: String, CaseIterable, Codable
{
    case assistant
    case playful
    case expert
    case socratic

    var prompt: String
    {
        switch self {
        case .assistant:
            return "You are a friendly and professional assistant. Provide clear, concise, and accurate responses. Use a polite tone and avoid unnecessary embellishment. Help the user achieve their goal efficiently."
        case .playful:
            return "You're a witty and imaginative AI who enjoys banter and pop culture references. Keep responses light-hearted, throw in the occasional joke, and use an informal, cheerful tone—while still being helpful."
        case .expert:
            return "Act like a senior software engineer or scientist. Respond with precise terminology and depth, include examples or analogies when needed, and don’t oversimplify unless asked to. Prioritize correctness over charm."
        case .socratic:
            return "You are a philosophical mentor who guides users to discover answers through questioning. Encourage reflection and critical thinking. Avoid giving direct answers unless asked; instead, ask clarifying questions and suggest lines of thought."
        }
    }

    var displayName: String
    {
        switch self {
        case .assistant: return "Helpful Assistant"
        case .playful: return "Playful Companion"
        case .expert: return "Technical Expert"
        case .socratic: return "Socratic Guide"
        }
    }
}

// MARK: - Model Configuration

struct ModelConfiguration: Identifiable, Codable, Equatable
{
    let id: UUID
    var name: String
    var displayName: String
    var host: String = "127.0.0.1"
    var port: Int
    var modelName: String
    var bubbleColor: CodableColor
    var personality: PersonalityPreset = .expert
    var enabled: Bool = true

    init(id: UUID = UUID(),
         name: String,
         displayName: String,
         host: String = "127.0.0.1",
         port: Int,
         modelName: String,
         bubbleColor: CodableColor,
         enabled: Bool = true)
    {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.host = host
        self.port = port
        self.modelName = modelName
        self.bubbleColor = bubbleColor
        self.enabled = enabled
    }

    var personalityPrompt: String {
        personality.prompt
    }

    static func randomPastelColor() -> Color
    {
        // Pastel colours have high lightness and low-medium saturation.
        let hue = Double.random(in: 0...1)
        let saturation = Double.random(in: 0.4...0.7)  // Not too saturated
        let brightness = Double.random(in: 0.85...1.0) // Keep it bright

        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }

    static func makeDefault(index: Int, avoiding existingColors: [CodableColor] = []) -> ModelConfiguration
    {
        let letter = Character(UnicodeScalar(65 + (index % 26))!) // 65 is "A"

        var color: Color
        var attempts = 0
        repeat {
            color = randomPastelColor()
            attempts += 1
        } while existingColors.contains(where: { $0.color.isApproximatelyEqual(to: color) }) && attempts < 50

        return ModelConfiguration(
            name: "Model \(letter)",
            displayName: "Model \(letter)",
            port: 11434,
            modelName: "",
            bubbleColor: CodableColor(color)
        )
    }
}

// MARK: - Codable Color Support

struct CodableColor: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double

    init(_ color: Color)
    {
        // Convert to sRGB color space to avoid crashes with system colors
        if let cgColor = color.cgColor,
           let srgbColor = cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil) {
            let components = srgbColor.components ?? [0, 0, 0, 1]
            self.red = Double(components[safe: 0] ?? 0)
            self.green = Double(components[safe: 1] ?? 0)
            self.blue = Double(components[safe: 2] ?? 0)
            self.opacity = Double(components[safe: 3] ?? 1)
        }
        else
        {
            // Fallback to a default color if conversion fails
            self.red = 0.5
            self.green = 0.5
            self.blue = 0.5
            self.opacity = 1.0
        }
    }

    init(red: Double, green: Double, blue: Double, opacity: Double = 1.0)
    {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    var color: Color
    {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}

// MARK: - Updated ChatMessage

struct ChatMessage: Identifiable, Equatable
{
    let id = UUID()
    var text: String
    let senderID: UUID  // References ModelConfiguration.id
    let senderName: String
    var isThink: Bool
    var isStreaming: Bool = false

    var isUser: Bool
    {
        senderID == UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    }

    static func userMessage(text: String) -> ChatMessage
    {
        ChatMessage(
            text: text,
            senderID: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            senderName: "User",
            isThink: false,
            isStreaming: false
        )
    }
}

// MARK: - Configuration Manager

@MainActor
class ModelConfigurationManager: ObservableObject
{
    @Published var configurations: [ModelConfiguration] = []
    @Published var viewModel: ChatViewModel?

    private let userDefaults = UserDefaults.standard
    private let configurationsKey = "model_configurations"

    init()
    {
        loadConfigurations()
    }

    var configurationColours: [Color]
    {
        configurations.indices.map(\.self).map { index in
            configurations[index].bubbleColor.color
        }
    }

    func loadConfigurations()
    {
        if let data = userDefaults.data(forKey: configurationsKey),
           let decoded = try? JSONDecoder().decode([ModelConfiguration].self, from: data)
        {
            configurations = decoded
        }
        else
        {
            // Create default configurations
            configurations = [
                ModelConfiguration.makeDefault(index: 0),
                ModelConfiguration.makeDefault(index: 1)
            ]
            saveConfigurations()
        }
    }

    func saveConfigurations()
    {
        if let encoded = try? JSONEncoder().encode(configurations) {
            userDefaults.set(encoded, forKey: configurationsKey)
        }
    }

    func addConfiguration()
    {
        let newConfig = ModelConfiguration.makeDefault(index: configurations.count, avoiding: configurations.map(\.bubbleColor))
        configurations.append(newConfig)
        saveConfigurations()
    }

    static var allPersonalityPresets: [PersonalityPreset] {
        PersonalityPreset.allCases
    }

    func removeConfiguration(at index: Int)
    {
        guard configurations.count > 1 else { return } // Keep at least one
        configurations.remove(at: index)
        saveConfigurations()
    }

    func updateConfiguration(_ config: ModelConfiguration)
    {
        if let index = configurations.firstIndex(where: { $0.id == config.id })
        {
            configurations[index] = config
            saveConfigurations()
        }
    }

    var enabledConfigurations: [ModelConfiguration]
    {
        configurations.filter { $0.enabled && !$0.modelName.isEmpty }
    }
}

// MARK: - Updated Chat Service Protocol

protocol ChatServiceProtocol
{
    func generateResponse(
        configuration: ModelConfiguration,
        prompt: String,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) -> Cancellable?
}

enum Errors: Swift.Error
{
    case invalidURL
}

// MARK: - Updated Ollama Service

class OllamaChatService: ChatServiceProtocol
{
    func generateResponse(
        configuration: ModelConfiguration,
        prompt: String,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) -> Cancellable?
    {
        guard let url = URL(string: "http://\(configuration.host):\(configuration.port)/api/generate") else {
            onComplete(.failure(Errors.invalidURL))
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

        let payload: [String: Any] = [
            "model": configuration.modelName,
            "prompt": prompt,
            "stream": true,
            "options": [
                "temperature": 0.7,
                "top_p": 0.9
            ]
        ]

        do
        {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }
        catch
        {
            onComplete(.failure(error))
            return nil
        }

        var accumulatedText = ""

        let delegate = StreamingDelegate(
            onChunk: { chunk in
                accumulatedText += chunk
                onChunk(chunk)
            },
            onFinish: {
                onComplete(.success(accumulatedText))
            }
        )

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: request)
        task.resume()

        return AnyCancellable
        {
            task.cancel()
        }
    }
}

private extension Color {
    func isApproximatelyEqual(to other: Color, threshold: Double = 0.05) -> Bool {
        let lhs = NSColor(self)
        let rhs = NSColor(other)
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        var rr: CGFloat = 0, rg: CGFloat = 0, rb: CGFloat = 0, ra: CGFloat = 0
        lhs.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
        rhs.getRed(&rr, green: &rg, blue: &rb, alpha: &ra)
        return abs(lr - rr) < threshold &&
               abs(lg - rg) < threshold &&
               abs(lb - rb) < threshold
    }
}
