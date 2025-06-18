//
//  ModelDescription.swift
//  RobotsMowingTheGrass
//
//  Created by Gregg Jaskiewicz on 13/06/2025.
//

import SwiftUI

// MARK: - Model Description (moved from SettingsPanel.swift)
struct ModelDescription: Hashable, Identifiable
{
    var id: String { name }
    let name: String
    let size: UInt64?
    let modifiedAt: Date?

    var displayString: String
    {
        var components: [String] = [name]

        if let size = size {
            components.append("(\(Self.formatSize(size)))")
        }

        return components.joined(separator: " ")
    }

    static func formatSize(_ bytes: UInt64) -> String
    {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct ModelSettingsPanel: View
{
    @EnvironmentObject var configManager: ModelConfigurationManager
    @Binding var maxTurns: Int
    @Binding var infinite: Bool
    @Binding var contextTurns: Int

    @State private var expandedConfigs: Set<UUID> = []

    var body: some View
    {
        ScrollView
        {
            VStack(alignment: .leading, spacing: 20)
            {
                modelsSection
                Divider()
                conversationSection
                Spacer(minLength: 20)
            }
            .padding()
        }
        .frame(minWidth: 320)
        .navigationTitle("Settings")
    }

    private var modelsSection: some View
    {
        VStack(alignment: .leading, spacing: 12)
        {
            HStack
            {
                Text("Models")
                    .font(.headline)

                Spacer()

                Button(action: { configManager.addConfiguration() })
                {
                    Image(systemName: "plus")
                }
            }

            ForEach(configManager.configurations.indices, id: \.self) { index in
                ModelConfigurationView(
                    configuration: $configManager.configurations[index],
                    isExpanded: expandedConfigs.contains(configManager.configurations[index].id),
                    onToggleExpanded: { toggleExpanded(configManager.configurations[index].id) },
                    onDelete: { configManager.removeConfiguration(at: index) },
                    onUpdate: { configManager.saveConfigurations() }
                )
            }
        }
    }

    private var conversationSection: some View
    {
        VStack(alignment: .leading, spacing: 12)
        {
            Text("Conversation Settings")
                .font(.headline)

            Toggle("Infinite turns", isOn: $infinite)

            if !infinite
            {
                HStack
                {
                    VStack(alignment: .leading)
                    {
                        Text("Max turns: \(maxTurns)")
                        Slider(value: Binding(
                            get: { Double(maxTurns) },
                            set: { maxTurns = Int($0) }
                        ), in: 1...50, step: 1)
                    }
                }
            }

            HStack
            {
                VStack(alignment: .leading)
                {
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

    private func toggleExpanded(_ id: UUID)
    {
        if expandedConfigs.contains(id)
        {
            expandedConfigs.remove(id)
        }
        else
        {
            expandedConfigs.insert(id)
        }
    }
}

// MARK: - Individual Model Configuration View

struct ModelConfigurationView: View
{
    @Binding var configuration: ModelConfiguration
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onDelete: () -> Void
    let onUpdate: () -> Void

    @State private var isLoadingModels = false
    @State private var availableModels: [ModelDescription] = []
    @State private var errorMessage: String?

    var body: some View
    {
        VStack(alignment: .leading, spacing: 8)
        {
            headerView

            if isExpanded
            {
                Divider()
                configurationDetails
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(configuration.bubbleColor.color.opacity(0.3), lineWidth: 1)
        )
    }

    private var headerView: some View
    {
        HStack
        {
            Toggle("", isOn: $configuration.enabled)
                .labelsHidden()
                .onChange(of: configuration.enabled) { onUpdate() }

            TextField("Name", text: $configuration.displayName)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(.body, weight: .medium))
                .onChange(of: configuration.displayName) { onUpdate() }

            if !configuration.modelName.isEmpty
            {
                Text(configuration.modelName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onToggleExpanded)
            {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var configurationDetails: some View
    {
        VStack(alignment: .leading, spacing: 12)
        {
            // Connection settings
            HStack {
                Text("Host:")
                    .frame(width: 60, alignment: .trailing)
                TextField("Host", text: $configuration.host)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: configuration.host) {
                        onUpdate()
                        fetchModels()
                    }
            }

            HStack
            {
                Text("Port:")
                    .frame(width: 60, alignment: .trailing)
                TextField("Port", value: $configuration.port, formatter: NumberFormatter())
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 80)
                    .onChange(of: configuration.port) {
                        onUpdate()
                        fetchModels()
                    }

                Button(action: fetchModels)
                {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoadingModels)

                Spacer()
            }

            // Model selection
            HStack
            {
                Text("Model:")
                    .frame(width: 60, alignment: .trailing)

                Picker("", selection: $configuration.modelName)
                {
                    if availableModels.isEmpty && !isLoadingModels
                    {
                        Text("No models available").tag("")
                    }
                    else
                    {
                        ForEach(availableModels) { model in
                            Text(model.displayString).tag(model.name)
                        }
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .disabled(availableModels.isEmpty || isLoadingModels)
                .onChange(of: configuration.modelName) { onUpdate() }
            }

            // Color picker
            HStack
            {
                Text("Color:")
                    .frame(width: 60, alignment: .trailing)

                ColorPicker("", selection: Binding(
                    get: { configuration.bubbleColor.color },
                    set: { configuration.bubbleColor = CodableColor($0); onUpdate() }
                ))
                .labelsHidden()

                Spacer()
            }

            // Personality preset picker
            HStack {
                Text("Personality:")
                    .frame(width: 90, alignment: .trailing)

                Picker("", selection: $configuration.personality) {
                    ForEach(PersonalityPreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .onChange(of: configuration.personality) { onUpdate() }

                Spacer()
            }

            if let error = errorMessage
            {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack
            {
                Spacer()
                Button("Delete", role: .destructive, action: onDelete)
                    .buttonStyle(.bordered)
            }
        }
        .onAppear { fetchModels() }
    }

    private func fetchModels()
    {
        guard let url = URL(string: "http://\(configuration.host):\(configuration.port)/api/tags") else {
            errorMessage = "Invalid URL"
            return
        }

        isLoadingModels = true
        errorMessage = nil

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async
            {
                isLoadingModels = false

                if let error = error
                {
                    errorMessage = "Connection failed: \(error.localizedDescription)"
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      let data = data else {
                    errorMessage = "Server error"
                    return
                }

                do {
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let models = json["models"] as? [[String: Any]] else {
                        errorMessage = "Invalid response format"
                        return
                    }

                    availableModels = models.compactMap { modelData in
                        guard let name = modelData["name"] as? String else { return nil }
                        let size = modelData["size"] as? UInt64
                        return ModelDescription(name: name, size: size, modifiedAt: nil)
                    }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

                } catch {
                    errorMessage = "Failed to parse response"
                }
            }
        }.resume()
    }
}
