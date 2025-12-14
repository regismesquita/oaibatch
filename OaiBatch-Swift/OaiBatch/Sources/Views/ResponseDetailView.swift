//
//  ResponseDetailView.swift
//  OaiBatch
//
//  View for viewing and fetching batch request responses.
//  Allows loading by request ID or batch ID, fetching responses, and copying to clipboard.
//

import SwiftUI
import AppKit

struct ResponseDetailView: View {
    @EnvironmentObject var dataStore: DataStore
    @Binding var selectedRequest: BatchRequest?

    // MARK: - State

    @State private var idInput: String = ""
    @State private var loadedRequest: BatchRequest?
    @State private var responseText: String = ""
    @State private var statusMessage: String = ""
    @State private var statusColor: Color = AppColors.textMuted
    @State private var isLoading: Bool = false
    @State private var openAIService: OpenAIService?

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("Response Details")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(AppColors.textPrimary)
                .padding(.bottom, 20)

            // ID Input Row
            idInputRow
                .padding(.bottom, 16)

            // Details Card
            detailsCard
                .padding(.bottom, 16)

            // Response Section
            responseSection

            Spacer(minLength: 0)

            // Status Message
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.system(size: 12))
                    .foregroundColor(statusColor)
                    .padding(.top, 16)
            }
        }
        .padding(24)
        .background(AppColors.bgDark)
        .onAppear {
            setupService()
            loadFromSelection()
        }
        .onChange(of: selectedRequest) { _ in
            loadFromSelection()
        }
    }

    // MARK: - ID Input Row

    private var idInputRow: some View {
        HStack(spacing: 12) {
            // Text Field
            TextField("Enter Request ID or Batch ID...", text: $idInput)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(AppColors.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(width: 300, height: 44)
                .background(AppColors.bgInput)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.border, lineWidth: 1)
                )

            // Load Button
            Button(action: loadDetails) {
                Text("Load")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(idInput.trimmingCharacters(in: .whitespaces).isEmpty)

            // Fetch Response Button
            Button(action: fetchResponse) {
                HStack(spacing: 6) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .progressViewStyle(CircularProgressViewStyle(tint: AppColors.bgDark))
                    }
                    Text("Fetch Response")
                }
            }
            .buttonStyle(GlowButtonStyle())
            .disabled(isLoading || idInput.trimmingCharacters(in: .whitespaces).isEmpty)

            // Copy Button
            Button(action: copyToClipboard) {
                Text("Copy")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(responseText.isEmpty)

            Spacer()
        }
    }

    // MARK: - Details Card

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let request = loadedRequest {
                detailRow(label: "Request ID", value: request.id)
                detailRow(label: "Batch ID", value: request.batchId)
                detailRow(label: "Status", value: request.status.displayName, valueColor: StatusColors.color(for: request.status))
                detailRow(label: "Model", value: request.model)
                detailRow(label: "Reasoning Effort", value: request.reasoningEffortDisplay)
                detailRow(label: "Created", value: request.formattedCreatedAt)
                detailRow(label: "Completed", value: request.formattedCompletedAt)
                detailRow(label: "Usage", value: request.formattedUsage)
            } else {
                Text("Load a request to see details")
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.textMuted)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func detailRow(label: String, value: String, valueColor: Color = AppColors.textSecondary) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(label):")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppColors.textMuted)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .font(.system(size: 13))
                .foregroundColor(valueColor)
                .textSelection(.enabled)

            Spacer()
        }
    }

    // MARK: - Response Section

    private var responseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Response")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(AppColors.textSecondary)

            TextEditor(text: $responseText)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(AppColors.textPrimary)
                .scrollContentBackground(.hidden)
                .background(AppColors.bgCard)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.border, lineWidth: 1)
                )
        }
    }

    // MARK: - Actions

    private func setupService() {
        if let apiKey = dataStore.getApiKey() {
            openAIService = OpenAIService(apiKey: apiKey)
        }
    }

    private func loadFromSelection() {
        guard let request = selectedRequest else { return }
        idInput = request.id
        loadedRequest = request
        responseText = request.response ?? ""
        setStatus("Loaded request: \(request.id)", color: AppColors.textMuted)
    }

    private func loadDetails() {
        let searchId = idInput.trimmingCharacters(in: .whitespaces)
        guard !searchId.isEmpty else {
            setStatus("Enter a request ID", color: AppColors.warning)
            return
        }

        guard let request = dataStore.findRequest(byIdOrBatchId: searchId) else {
            setStatus("Request not found", color: AppColors.error)
            loadedRequest = nil
            responseText = ""
            return
        }

        loadedRequest = request
        responseText = request.response ?? ""
        setStatus("Loaded request: \(request.id)", color: AppColors.success)
    }

    private func fetchResponse() {
        let searchId = idInput.trimmingCharacters(in: .whitespaces)
        guard !searchId.isEmpty else {
            setStatus("Enter a request ID", color: AppColors.warning)
            return
        }

        guard let service = openAIService else {
            setStatus("API key not configured", color: AppColors.error)
            return
        }

        // Try to find the request first
        guard let request = dataStore.findRequest(byIdOrBatchId: searchId) ?? loadedRequest else {
            setStatus("Request not found", color: AppColors.error)
            return
        }

        isLoading = true
        setStatus("Fetching response...", color: AppColors.textMuted)

        Task {
            do {
                let (updatedRequest, text) = try await service.fetchResponse(for: request)

                await MainActor.run {
                    loadedRequest = updatedRequest
                    responseText = text
                    dataStore.updateRequest(updatedRequest)
                    isLoading = false
                    setStatus("Response fetched successfully", color: AppColors.success)
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    setStatus("Error: \(error.localizedDescription)", color: AppColors.error)
                }
            }
        }
    }

    private func copyToClipboard() {
        let textToCopy = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToCopy.isEmpty else {
            setStatus("No response to copy", color: AppColors.warning)
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)
        setStatus("Copied to clipboard!", color: AppColors.success)
    }

    private func setStatus(_ message: String, color: Color) {
        statusMessage = message
        statusColor = color
    }
}

// MARK: - Preview

#if DEBUG
struct ResponseDetailView_Previews: PreviewProvider {
    static var previews: some View {
        ResponseDetailView(selectedRequest: .constant(nil))
            .environmentObject(DataStore())
            .frame(width: 800, height: 600)
    }
}
#endif
