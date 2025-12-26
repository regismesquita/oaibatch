//
//  RequestsListView.swift
//  OaiBatch
//
//  List view showing all batch requests with status badges.
//  Displays requests in reverse chronological order (newest first).
//

import SwiftUI
import AppKit

struct RequestsListView: View {
    @EnvironmentObject var dataStore: DataStore
    @Binding var selectedRequest: BatchRequest?

    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var openAIService: OpenAIService?

    /// Requests sorted in reverse chronological order (newest first)
    private var sortedRequests: [BatchRequest] {
        dataStore.requests.reversed()
    }

    /// Check if API key is available
    private var hasApiKey: Bool {
        dataStore.getApiKey() != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header row with title and refresh button
            headerRow

            Divider()
                .background(AppColors.border)

            // Error message banner
            if let error = errorMessage {
                errorBanner(error)
            }

            // Request list or empty state
            if dataStore.requests.isEmpty {
                emptyState
            } else {
                requestsList
            }
        }
        .background(AppColors.bgDark)
        .onAppear {
            initializeService()
        }
        .onChange(of: dataStore.apiKey) { _, newValue in
            if let apiKey = newValue ?? dataStore.getApiKey() {
                openAIService = OpenAIService(apiKey: apiKey)
            }
        }
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack {
            Text("Batch Requests")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            // Refresh button with loading indicator
            Button(action: refreshStatuses) {
                HStack(spacing: 6) {
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .progressViewStyle(CircularProgressViewStyle(tint: AppColors.bgDark))
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Refresh")
                }
            }
            .buttonStyle(GlowButtonStyle())
            .disabled(isRefreshing || !hasApiKey)
        }
        .padding(24)
        .background(AppColors.bgDark)
    }

    // MARK: - Error Banner

    private func errorBanner(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppColors.error)
            Text(error)
                .font(.system(size: 13))
                .foregroundColor(AppColors.error)
            Spacer()
            Button("Dismiss") {
                errorMessage = nil
            }
            .buttonStyle(.plain)
            .foregroundColor(AppColors.textSecondary)
        }
        .padding(12)
        .background(AppColors.error.opacity(0.1))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(AppColors.textMuted)
            Text("No requests yet.")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppColors.textPrimary)
            Text("Create your first batch request!")
                .font(.system(size: 14))
                .foregroundColor(AppColors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Requests List

    private var requestsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Show requests in reverse chronological order (newest first)
                ForEach(sortedRequests) { request in
                    RequestCard(
                        request: request,
                        onClick: {
                            selectedRequest = request
                        }
                    )
                    .contextMenu {
                        Button("View Details") {
                            selectedRequest = request
                        }
                        Button("Copy Request ID") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(request.id, forType: .string)
                        }
                        if !request.batchId.isEmpty {
                            Button("Copy Batch ID") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(request.batchId, forType: .string)
                            }
                        }

                        Divider()
                        Button("Copy User Prompt") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(request.prompt, forType: .string)
                        }
                        Button("Copy System Prompt") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(request.systemPrompt, forType: .string)
                        }
                        Button("Copy Full Prompt") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(combinedPrompt(for: request), forType: .string)
                        }

                        Divider()
                        Button("Delete", role: .destructive) {
                            dataStore.deleteRequest(byId: request.id)
                        }
                    }
                }
            }
            .padding(24)
        }
        .scrollIndicators(.automatic)
    }

    // MARK: - Actions

    private func initializeService() {
        if let apiKey = dataStore.getApiKey() {
            openAIService = OpenAIService(apiKey: apiKey)
        }
    }

    private func refreshStatuses() {
        guard let service = openAIService else {
            errorMessage = "API key not configured"
            return
        }

        isRefreshing = true
        errorMessage = nil

        Task {
            do {
                let updatedRequests = try await service.refreshStatuses(requests: dataStore.requests)
                await MainActor.run {
                    for request in updatedRequests {
                        dataStore.updateRequest(request)
                    }
                    isRefreshing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isRefreshing = false
                }
            }
        }
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

#Preview {
    RequestsListView(selectedRequest: .constant(nil))
        .environmentObject(DataStore())
        .frame(width: 800, height: 600)
}
