//
//  OaiBatchApp.swift
//  OaiBatch
//
//  Main app entry point for the OaiBatch macOS application.
//

import SwiftUI

@main
struct OaiBatchApp: App {
    @StateObject private var dataStore = DataStore()

    var body: some Scene {
        WindowGroup("oaibatch") {
            ContentView()
                .environmentObject(dataStore)
                .frame(minWidth: 1100, minHeight: 750)
                .background(AppColors.bgDark)
                .preferredColorScheme(.dark)
                .onAppear {
                    // Configure window appearance for dark mode
                    NSApp.appearance = NSAppearance(named: .darkAqua)
                    
                    // Ensure config and requests are loaded (DataStore.init already does this,
                    // but we can trigger a refresh here if needed)
                    dataStore.loadConfig()
                    dataStore.loadRequests()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 750)
        .commands {
            // Remove the default "New" menu item
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
                .environmentObject(dataStore)
                .preferredColorScheme(.dark)
        }
    }
}
