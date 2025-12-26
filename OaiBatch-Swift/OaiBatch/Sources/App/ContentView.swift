//
//  ContentView.swift
//  OaiBatch
//
//  Main content view with NavigationSplitView for sidebar and detail navigation.
//

import SwiftUI

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var selection: NavigationItem? = .create
    @State private var selectedRequest: BatchRequest?

    /// Whether the API key is available for non-settings views
    private var isApiKeyAvailable: Bool {
        dataStore.getApiKey() != nil
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selection: $selection,
                isAPIKeyAvailable: isApiKeyAvailable,
                onRequestsTapped: { selectedRequest = nil }
            )
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.bgDark)
        }
        .navigationSplitViewStyle(.balanced)
        .background(AppColors.bgDark)
        .onChange(of: selection) { _, newValue in
            // Clear selected request when navigating away from requests
            if newValue != .requests {
                selectedRequest = nil
            }
        }
        .onAppear {
            // If no API key is available, redirect to settings
            if !isApiKeyAvailable {
                selection = .settings
            }
        }
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        if !isApiKeyAvailable && selection != .settings {
            // Gate non-settings views if API key is not available
            apiKeyRequiredView
        } else {
            switch selection {
            case .create:
                CreateRequestView()
                    .environmentObject(dataStore)

            case .requests:
                requestsDetailView

            case .settings:
                SettingsView()
                    .environmentObject(dataStore)

            case .none:
                placeholderView
            }
        }
    }

    @ViewBuilder
    private var requestsDetailView: some View {
        if selectedRequest != nil {
            ResponseDetailView(selectedRequest: $selectedRequest)
                .environmentObject(dataStore)
        } else {
            RequestsListView(selectedRequest: $selectedRequest)
                .environmentObject(dataStore)
        }
    }

    private var apiKeyRequiredView: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundColor(AppColors.textMuted)

            Text("API Key Required")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textPrimary)

            Text("Please configure your OpenAI API key in Settings to use this feature.")
                .font(.body)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Button("Go to Settings") {
                selection = .settings
            }
            .buttonStyle(GlowButtonStyle())
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.bgDark)
    }

    private var placeholderView: some View {
        VStack(spacing: 12) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 36))
                .foregroundColor(AppColors.textMuted)

            Text("Select an item from the sidebar")
                .font(.body)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.bgDark)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(DataStore())
        .frame(width: 1100, height: 750)
}
