//
//  SettingsView.swift
//  OaiBatch
//
//  Settings view for API key configuration.
//  macOS 13+
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var dataStore: DataStore

    @State private var apiKeyInput = ""
    @State private var isApiKeyVisible = false
    @State private var statusMessage: String = ""
    @State private var statusColor: Color = AppColors.textMuted

    /// Whether an API key is currently configured (env var or saved)
    private var hasApiKey: Bool {
        dataStore.getApiKey() != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // MARK: - Header
                Text("Settings")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)

                // MARK: - API Key Card
                VStack(alignment: .leading, spacing: 16) {
                    // Hint text explaining storage location
                    Text("Enter your OpenAI API key. It will be stored locally in:")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.textMuted)

                    Text("~/.oaibatch/config.json")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(AppColors.textSecondary)

                    // Note about environment variable override
                    Text("Note: OPENAI_API_KEY environment variable overrides the saved key.")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.textMuted)
                        .padding(.top, 4)

                    // API Key label
                    Text("API Key")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppColors.textSecondary)
                        .padding(.top, 8)

                    // SecureField with show/hide toggle
                    HStack(spacing: 12) {
                        Group {
                            if isApiKeyVisible {
                                TextField("sk-...", text: $apiKeyInput)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 14, design: .monospaced))
                            } else {
                                SecureField("sk-...", text: $apiKeyInput)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 14, design: .monospaced))
                            }
                        }
                        .foregroundColor(AppColors.textPrimary)

                        // Show/hide toggle button
                        Button(action: {
                            isApiKeyVisible.toggle()
                        }) {
                            Image(systemName: isApiKeyVisible ? "eye.slash" : "eye")
                                .foregroundColor(AppColors.textSecondary)
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help(isApiKeyVisible ? "Hide API key" : "Show API key")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppColors.bgInput)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppColors.border, lineWidth: 1)
                    )

                    // Save Key button
                    Button("Save Key") {
                        saveApiKey()
                    }
                    .buttonStyle(GlowButtonStyle())
                    .padding(.top, 8)

                    // Status message
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.system(size: 13))
                            .foregroundColor(statusColor)
                            .padding(.top, 4)
                    }
                }
                .padding(24)
                .background(AppColors.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppColors.border, lineWidth: 1)
                )

                Spacer()
            }
            .padding(24)
        }
        .background(AppColors.bgDark)
        .onAppear {
            updateStatusMessage()
        }
        .onChange(of: dataStore.apiKey) { _ in
            updateStatusMessage()
        }
    }

    // MARK: - Private Methods

    /// Update the status message based on current API key state
    private func updateStatusMessage() {
        if hasApiKey {
            statusMessage = "API key is configured"
            statusColor = AppColors.success
        } else {
            statusMessage = "API key required to use the app"
            statusColor = AppColors.warning
        }
    }

    /// Validate and save the API key
    private func saveApiKey() {
        let key = apiKeyInput

        // Validation: key cannot be empty
        guard !key.isEmpty else {
            statusMessage = "API key cannot be empty"
            statusColor = AppColors.error
            return
        }

        // Validation: key cannot contain whitespace
        if key.contains(where: { $0.isWhitespace }) {
            statusMessage = "API key cannot contain whitespace"
            statusColor = AppColors.error
            return
        }

        // Attempt to save
        do {
            try dataStore.saveConfig(apiKey: key)

            // Clear input field after successful save (for privacy)
            apiKeyInput = ""

            // Show success message
            statusMessage = "API key saved successfully"
            statusColor = AppColors.success
        } catch {
            // Show error message
            statusMessage = "Error: \(error.localizedDescription)"
            statusColor = AppColors.error
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    SettingsView()
        .environmentObject(DataStore())
        .frame(width: 600, height: 500)
}
#endif
