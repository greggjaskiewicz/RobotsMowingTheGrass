//
//  SettingsPanel.swift
//  RobotsMowingTheGrass
//
//  Created by Gregg Jaskiewicz on 12/06/2025.
//

import SwiftUI

struct ModelDesc: Hashable, Identifiable {
    var id: String { name }
    let name: String
    let size: UInt64?

    var displayString: String {
        if let size = size {
            return "\(name) (\(Self.formatSize(size)))"
        } else {
            return name
        }
    }

    static func formatSize(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct SettingsPanel: View {
    @Binding var portA: Int
    @Binding var portB: Int
    @Binding var selectedModelA: String
    @Binding var selectedModelB: String
    @Binding var maxTurns: Int
    @Binding var infinite: Bool
    @State private var modelsA: [ModelDesc] = []
    @State private var modelsB: [ModelDesc] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Server A")
                .font(.headline)
            HStack {
                Text("Port:")
                TextField("", value: $portA, formatter: NumberFormatter())
                    .frame(width: 70)
                    .onChange(of: portA) { _ in fetchModelsA() }
            }
            Picker("Model:", selection: $selectedModelA) {
                ForEach(modelsA) { model in
                    Text(model.displayString).tag(model.name)
                }
            }.onAppear(perform: fetchModelsA)

            Divider()

            Text("Server B")
                .font(.headline)
            HStack {
                Text("Port:")
                TextField("", value: $portB, formatter: NumberFormatter())
                    .frame(width: 70)
                    .onChange(of: portB) { _ in fetchModelsB() }
            }
            Picker("Model:", selection: $selectedModelB) {
                ForEach(modelsB) { model in
                    Text(model.displayString).tag(model.name)
                }
            }.onAppear(perform: fetchModelsB)

            Divider()
            HStack {
                Toggle("Infinite", isOn: $infinite)
                if !infinite {
                    Stepper("Turns: \(maxTurns)", value: $maxTurns, in: 1...100)
                        .frame(width: 140)
                }
            }
            Spacer()
        }
        .padding()
        .frame(minWidth: 240)
    }

    // --- Ollama model list query ---
    func fetchModelsA() { fetchModels(for: portA) { modelsA = $0 } }
    func fetchModelsB() { fetchModels(for: portB) { modelsB = $0 } }

    func fetchModels(for port: Int, completion: @escaping ([ModelDesc]) -> Void) {
        guard let url = URL(string: "http://localhost:\(port)/api/tags") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = obj["models"] as? [[String: Any]] {
                let result: [ModelDesc] = models.compactMap {
                    guard let name = $0["name"] as? String else { return nil }
                    let size = $0["size"] as? UInt64
                    return ModelDesc(name: name, size: size)
                }
                DispatchQueue.main.async { completion(result) }
            }
        }.resume()
    }
}
