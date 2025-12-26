//
//  ResponseDetailView.swift
//  OaiBatch
//
//  View for viewing and fetching batch request responses.
//  Allows loading by request ID or batch ID, fetching responses, and copying to clipboard.
//

import SwiftUI
import AppKit

// MARK: - High-Performance Text View (NSTextView wrapper)

/// NSTextView wrapper for displaying large text efficiently.
/// SwiftUI's TextEditor has poor performance with large text content.
struct HighPerformanceTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = false
    var font: NSFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    var textColor: NSColor = NSColor(AppColors.textPrimary)
    var backgroundColor: NSColor = NSColor(AppColors.bgCard)

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.font = font
        textView.textColor = textColor
        textView.backgroundColor = backgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        // Disable automatic layout for better performance with large text
        textView.layoutManager?.allowsNonContiguousLayout = true

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = backgroundColor

        textView.delegate = context.coordinator

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Only update if text actually changed to avoid unnecessary redraws
        if textView.string != text {
            // Preserve scroll position
            let visibleRect = textView.visibleRect

            textView.string = text

            // Restore scroll position
            textView.scrollToVisible(visibleRect)
        }

        textView.font = font
        textView.textColor = textColor
        textView.backgroundColor = backgroundColor
        scrollView.backgroundColor = backgroundColor
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighPerformanceTextView

        init(_ parent: HighPerformanceTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if parent.isEditable {
                parent.text = textView.string
            }
        }
    }
}

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
            headerRow
                .padding(.bottom, 20)

            // ID Input Row
            idInputRow
                .padding(.bottom, 16)

            // Details Card
            detailsCard
                .padding(.bottom, 16)

            promptSection
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

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 12) {
            if selectedRequest != nil {
                Button(action: {
                    clearLocalState()
                    selectedRequest = nil
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Back to Requests")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            Text("Response Details")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(AppColors.textPrimary)

            Spacer()
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

            Button(action: copyToClipboard) {
                Text("Copy Response")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button(action: copyUserPrompt) {
                Text("Copy User Prompt")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(loadedRequest == nil)

            Button(action: copySystemPrompt) {
                Text("Copy System Prompt")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(loadedRequest == nil)

            Button(action: copyFullPrompt) {
                Text("Copy Full Prompt")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(loadedRequest == nil)

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
                detailRow(label: "Web Search", value: request.webSearchEnabled ? "enabled" : "disabled")
                if request.webSearchEnabled {
                    detailRow(label: "Search Context", value: request.webSearchContextSize ?? "-")
                }
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

    // MARK: - Prompt Section

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Prompt")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(AppColors.textSecondary)

            if let request = loadedRequest {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("System Prompt")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppColors.textMuted)
                        promptBox(request.systemPrompt)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("User Prompt")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppColors.textMuted)
                        promptBox(request.prompt)
                    }
                }
            } else {
                Text("Load a request to view prompts")
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.textMuted)
            }
        }
    }

    private func promptBox(_ text: String) -> some View {
        HighPerformanceTextView(
            text: .constant(text),
            isEditable: false
        )
        .frame(maxWidth: .infinity)
        .frame(minHeight: 90, maxHeight: 180)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    // MARK: - Response Section

    private var responseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Response")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(AppColors.textSecondary)

            HighPerformanceTextView(text: $responseText)
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
        guard let request = selectedRequest else {
            clearLocalState()
            return
        }
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
        copyStringToClipboard(textToCopy, successMessage: "Copied response to clipboard!")
    }

    private func setStatus(_ message: String, color: Color) {
        statusMessage = message
        statusColor = color
    }

    private func clearLocalState() {
        loadedRequest = nil
        idInput = ""
        responseText = ""
        statusMessage = ""
        statusColor = AppColors.textMuted
        isLoading = false
    }

    private func copyStringToClipboard(_ text: String, successMessage: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setStatus("Nothing to copy", color: AppColors.warning)
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
        setStatus(successMessage, color: AppColors.success)
    }

    private func copyUserPrompt() {
        guard let request = loadedRequest else {
            setStatus("Load a request first", color: AppColors.warning)
            return
        }
        copyStringToClipboard(request.prompt, successMessage: "Copied user prompt to clipboard!")
    }

    private func copySystemPrompt() {
        guard let request = loadedRequest else {
            setStatus("Load a request first", color: AppColors.warning)
            return
        }
        copyStringToClipboard(request.systemPrompt, successMessage: "Copied system prompt to clipboard!")
    }

    private func copyFullPrompt() {
        guard let request = loadedRequest else {
            setStatus("Load a request first", color: AppColors.warning)
            return
        }
        copyStringToClipboard(combinedPrompt(for: request), successMessage: "Copied full prompt to clipboard!")
    }

    private func combinedPrompt(for request: BatchRequest) -> String {
        """
        SYSTEM:
        \(request.systemPrompt)

        USER:
        \(request.prompt)
        """
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
