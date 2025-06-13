//
//  SettingsPanel.swift
//  RobotsMowingTheGrass
//
//  Created by Gregg Jaskiewicz on 12/06/2025.
//

import SwiftUI

struct ModelDescription: Hashable, Identifiable {
    var id: String { name }
    let name: String
    let size: UInt64?
    let modifiedAt: Date?

    var displayString: String {
        var components: [String] = [name]

        if let size = size {
            components.append("(\(Self.formatSize(size)))")
        }

        return components.joined(separator: " ")
    }

    static func formatSize(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowsNonnumericFormatting = false
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
    @Binding var contextTurns: Int

    @State private var modelsA: [ModelDescription] = []
    @State private var modelsB: [ModelDescription] = []
    @State private var isLoadingA = false
    @State private var isLoadingB = false
    @State private var errorMessageA: String?
    @State private var errorMessageB: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                serverSection(
                    title: "Server A",
                    port: $portA,
                    selectedModel: $selectedModelA,
                    models: modelsA,
                    isLoading: isLoadingA,
                    errorMessage: errorMessageA,
                    refreshAction: fetchModelsA
                )

                Divider()

                serverSection(
                    title: "Server B",
                    port: $portB,
                    selectedModel: $selectedModelB,
                    models: modelsB,
                    isLoading: isLoadingB,
                    errorMessage: errorMessageB,
                    refreshAction: fetchModelsB
                )

                Divider()

                conversationSection

                Spacer(minLength: 20)
            }
            .padding()
        }
        .frame(minWidth: 280)
        .navigationTitle("Settings")
    }

    @ViewBuilder
    private func serverSection(
        title: String,
        port: Binding<Int>,
        selectedModel: Binding<String>,
        models: [ModelDescription],
        isLoading: Bool,
        errorMessage: String?,
        refreshAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            HStack {
                Text("Port:")
                TextField("Port", value: port, formatter: NumberFormatter())
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 80)
                    .onChange(of: port.wrappedValue) { _ in
                        refreshAction()
                    }

                Button(action: refreshAction) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }

            VStack(alignment: .leading, spacing: 6) {

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.vertical, 2)
                }

                Picker("Model", selection: selectedModel) {
                    if models.isEmpty && !isLoading {
                        Text("No models available").tag("")
                    } else {
                        ForEach(models) { model in
                            Text(model.displayString)
                                .tag(model.name)
                        }
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .disabled(models.isEmpty || isLoading)
            }
        }
        .onAppear {
            refreshAction()
        }
    }

    private var conversationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conversation Settings")
                .font(.headline)

            Toggle("Infinite turns", isOn: $infinite)

            if !infinite {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Max turns: \(maxTurns)")
                        Slider(value: Binding(
                            get: { Double(maxTurns) },
                            set: { maxTurns = Int($0) }
                        ), in: 1...50, step: 1)
                    }
                }
            }

            HStack {
                VStack(alignment: .leading) {
                    Text("Context turns: \(contextTurns)")
                    Slider(value: Binding(
                        get: { Double(contextTurns) },
                        set: { contextTurns = Int($0) }
                    ), in: 1...50, step: 1)
                }
            }

            Text("Context turns determines how many recent messages are included when generating responses.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Model Fetching

    private func fetchModelsA() {
        fetchModels(for: portA, isLoadingBinding: { isLoadingA = $0 }) { models, error in
            modelsA = models
            errorMessageA = error
        }
    }

    private func fetchModelsB() {
        fetchModels(for: portB, isLoadingBinding: { isLoadingB = $0 }) { models, error in
            modelsB = models
            errorMessageB = error
        }
    }

    private func fetchModels(
        for port: Int,
        isLoadingBinding: @escaping (Bool) -> Void,
        completion: @escaping ([ModelDescription], String?) -> Void
    ) {
        guard let url = URL(string: "http://localhost:\(port)/api/tags") else {
            completion([], "Invalid URL")
            return
        }

        isLoadingBinding(true)

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoadingBinding(false)

                if let error = error {
                    completion([], "Connection failed: \(error.localizedDescription)")
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    completion([], "Invalid response")
                    return
                }

                guard httpResponse.statusCode == 200 else {
                    completion([], "Server error: \(httpResponse.statusCode)")
                    return
                }

                guard let data = data else {
                    completion([], "No data received")
                    return
                }

                do {
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let models = json["models"] as? [[String: Any]] else {
                        completion([], "Invalid JSON format")
                        return
                    }

                    let modelDescriptions: [ModelDescription] = models.compactMap { modelData in
                        guard let name = modelData["name"] as? String else { return nil }

                        let size = modelData["size"] as? UInt64
                        let modifiedAt = parseDate(from: modelData["modified_at"])

                        return ModelDescription(name: name, size: size, modifiedAt: modifiedAt)
                    }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

                    completion(modelDescriptions, nil)

                } catch {
                    completion([], "Failed to parse JSON: \(error.localizedDescription)")
                }
            }
        }.resume()
    }

    private func parseDate(from value: Any?) -> Date? {
        guard let dateString = value as? String else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: dateString)
    }
}

#Preview {
    SettingsPanel(
        portA: .constant(11434),
        portB: .constant(11435),
        selectedModelA: .constant("llama2"),
        selectedModelB: .constant("codellama"),
        maxTurns: .constant(8),
        infinite: .constant(false),
        contextTurns: .constant(12)
    )
}
