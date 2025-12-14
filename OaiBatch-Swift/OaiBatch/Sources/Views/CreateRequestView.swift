//
//  CreateRequestView.swift
//  OaiBatch
//
//  Form for creating new batch requests.
//

import SwiftUI

struct CreateRequestView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var openAIService: OpenAIService?

    // Form state
    @State private var systemPrompt = "You are a helpful assistant."
    @State private var userPrompt = ""
    @State private var selectedModel = Config.DEFAULT_MODEL
    @State private var maxTokensText = "100000"
    @State private var selectedReasoningEffort = Config.DEFAULT_REASONING_EFFORT

    // UI state
    @State private var isSubmitting = false
    @State private var statusMessage: String?
    @State private var isError = false

    // Focus state
    @FocusState private var systemPromptFocused: Bool
    @FocusState private var maxTokensFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                Text("New Batch Request")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)

                // Form Card
                VStack(alignment: .leading, spacing: 20) {
                    // System Prompt
                    FormField(label: "System Prompt") {
                        TextField("You are a helpful assistant.", text: $systemPrompt)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.textPrimary)
                            .focused($systemPromptFocused)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .frame(height: 44)
                            .background(AppColors.bgInput)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        systemPromptFocused ? AppColors.borderFocus : AppColors.border,
                                        lineWidth: 1
                                    )
                            )
                    }

                    // Settings Row
                    HStack(alignment: .top, spacing: 16) {
                        // Model Picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Model")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppColors.textSecondary)

                            Picker("Model", selection: $selectedModel) {
                                ForEach(Array(Config.MODEL_PRICING.keys).sorted(), id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 230, height: 44)
                            .background(AppColors.bgInput)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppColors.border, lineWidth: 1)
                            )

                            // Model pricing hint
                            Text(Config.formattedPricing(for: selectedModel))
                                .font(.system(size: 10))
                                .foregroundColor(AppColors.textMuted)
                        }

                        // Reasoning Effort Picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Reasoning Effort")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppColors.textSecondary)

                            Picker("Reasoning Effort", selection: $selectedReasoningEffort) {
                                ForEach(Config.REASONING_EFFORT_CHOICES, id: \.self) { effort in
                                    Text(effort).tag(effort)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 190, height: 44)
                            .background(AppColors.bgInput)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppColors.border, lineWidth: 1)
                            )

                            Text("Use \"none\" to disable")
                                .font(.system(size: 10))
                                .foregroundColor(AppColors.textMuted)
                        }

                        // Max Output Tokens
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Max Output Tokens")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppColors.textSecondary)

                            TextField("100000", text: $maxTokensText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14))
                                .foregroundColor(AppColors.textPrimary)
                                .focused($maxTokensFocused)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .frame(width: 160, height: 44)
                                .background(AppColors.bgInput)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(
                                            maxTokensFocused ? AppColors.borderFocus : AppColors.border,
                                            lineWidth: 1
                                        )
                                )
                        }

                        Spacer()
                    }

                    // User Prompt
                    FormField(label: "Your Prompt") {
                        TextEditor(text: $userPrompt)
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.textPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(minHeight: 200)
                            .background(AppColors.bgInput)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppColors.border, lineWidth: 1)
                            )
                    }

                    // Button Row with Status
                    HStack(spacing: 16) {
                        Button(action: submitRequest) {
                            HStack(spacing: 8) {
                                if isSubmitting {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .progressViewStyle(CircularProgressViewStyle(tint: AppColors.bgDark))
                                }
                                Text(isSubmitting ? "Creating..." : "Create Batch Request")
                            }
                        }
                        .buttonStyle(GlowButtonStyle())
                        .disabled(
                            userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            isSubmitting ||
                            !dataStore.hasApiKey
                        )

                        // Status Message
                        if let message = statusMessage {
                            Text(message)
                                .font(.system(size: 13))
                                .foregroundColor(isError ? AppColors.error : AppColors.success)
                        }
                    }

                    // API Key Warning
                    if !dataStore.hasApiKey {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AppColors.warning)
                            Text("Please configure your API key in Settings")
                                .font(.system(size: 12))
                                .foregroundColor(AppColors.warning)
                        }
                    }
                }
                .padding(24)
                .cardStyle(cornerRadius: 16)

                Spacer()
            }
            .padding(24)
        }
        .background(AppColors.bgDark)
        .onAppear {
            initializeService()
        }
        .onChange(of: dataStore.apiKey) { _ in
            initializeService()
        }
    }

    // MARK: - Private Methods

    private func initializeService() {
        if let apiKey = dataStore.getApiKey() {
            openAIService = OpenAIService(apiKey: apiKey)
        }
    }

    private func submitRequest() {
        guard let service = openAIService else {
            statusMessage = "API key not configured"
            isError = true
            return
        }

        let prompt = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            statusMessage = "Prompt cannot be empty"
            isError = true
            return
        }

        // Validate max tokens
        guard let maxTokens = Int(maxTokensText.trimmingCharacters(in: .whitespaces)),
              maxTokens > 0 else {
            statusMessage = "Invalid max tokens"
            isError = true
            return
        }

        isSubmitting = true
        statusMessage = nil
        isError = false

        Task {
            do {
                // Normalize reasoning effort - pass nil if "none"
                let reasoningEffort = Config.normalizeReasoningEffort(selectedReasoningEffort)

                let request = try await service.createBatchRequest(
                    prompt: prompt,
                    systemPrompt: systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "You are a helpful assistant."
                        : systemPrompt,
                    maxTokens: maxTokens,
                    model: selectedModel,
                    reasoningEffort: reasoningEffort
                )

                await MainActor.run {
                    dataStore.addRequest(request)
                    statusMessage = "Created: \(request.id)"
                    isError = false
                    // Clear the prompt for next request
                    userPrompt = ""
                    isSubmitting = false
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Error: \(error.localizedDescription.prefix(50))"
                    isError = true
                    isSubmitting = false
                }
            }
        }
    }
}

// MARK: - Form Field Component

struct FormField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppColors.textSecondary)
            content
        }
    }
}

// MARK: - DataStore Extension

extension DataStore {
    var hasApiKey: Bool {
        getApiKey() != nil
    }
}

// MARK: - Preview

#if DEBUG
struct CreateRequestView_Previews: PreviewProvider {
    static var previews: some View {
        CreateRequestView()
            .environmentObject(DataStore())
            .frame(width: 800, height: 700)
    }
}
#endif
