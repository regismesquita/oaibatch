//
//  DataStore.swift
//  OaiBatch
//
//  Data persistence for batch requests and configuration.
//

import Foundation
import Combine

/// ObservableObject for managing persistent data storage
@MainActor
final class DataStore: ObservableObject {

    // MARK: - File Paths (using Config constants)

    static var dataDirectory: URL { Config.dataDirectory }
    static var requestsFile: URL { Config.requestsFile }
    static var configFile: URL { Config.configFile }

    // MARK: - Published Properties

    @Published var requests: [BatchRequest] = []
    @Published var apiKey: String?

    // MARK: - Initialization

    init() {
        ensureDataDirectory()
        loadConfig()
        loadRequests()
    }

    // MARK: - Directory Management

    private func ensureDataDirectory() {
        let fileManager = FileManager.default
        let path = Self.dataDirectory.path

        if !fileManager.fileExists(atPath: path) {
            do {
                try fileManager.createDirectory(
                    at: Self.dataDirectory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                print("[DataStore] Failed to create data directory: \(error)")
            }
        }
    }

    // MARK: - Request Persistence

    func loadRequests() {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: Self.requestsFile.path) else {
            requests = []
            return
        }

        do {
            let data = try Data(contentsOf: Self.requestsFile)
            // BatchRequest handles its own Codable with snake_case keys
            let decoder = JSONDecoder()
            requests = try decoder.decode([BatchRequest].self, from: data)
        } catch {
            print("[DataStore] Failed to load requests: \(error)")
            requests = []
        }
    }

    func saveRequests() {
        ensureDataDirectory()

        do {
            // BatchRequest handles its own Codable with snake_case keys
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(requests)
            try data.write(to: Self.requestsFile, options: .atomic)
        } catch {
            print("[DataStore] Failed to save requests: \(error)")
        }
    }

    /// Add a new request and save
    func addRequest(_ request: BatchRequest) {
        requests.append(request)
        saveRequests()
    }

    /// Update a request by ID and save
    func updateRequest(_ request: BatchRequest) {
        if let index = requests.firstIndex(where: { $0.id == request.id }) {
            requests[index] = request
            saveRequests()
        }
    }

    /// Find a request by custom ID or batch ID
    func findRequest(byIdOrBatchId identifier: String) -> BatchRequest? {
        requests.first { $0.id == identifier || $0.batchId == identifier }
    }

    /// Delete a request by ID
    func deleteRequest(byId id: String) {
        requests.removeAll { $0.id == id }
        saveRequests()
    }

    // MARK: - Config Persistence

    func loadConfig() {
        // First check environment variable (takes precedence)
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
           !envKey.trimmingCharacters(in: .whitespaces).isEmpty {
            apiKey = envKey.trimmingCharacters(in: .whitespaces)
            return
        }

        // Then check config file
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: Self.configFile.path) else {
            apiKey = nil
            return
        }

        do {
            let data = try Data(contentsOf: Self.configFile)
            if let config = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let key = config["api_key"] as? String,
               !key.trimmingCharacters(in: .whitespaces).isEmpty {
                apiKey = key.trimmingCharacters(in: .whitespaces)
            }
        } catch {
            print("[DataStore] Failed to load config: \(error)")
            apiKey = nil
        }
    }

    func saveConfig(apiKey newKey: String) throws {
        let key = newKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else {
            throw DataStoreError.emptyApiKey
        }

        ensureDataDirectory()

        let config: [String: Any] = ["api_key": key]
        let data = try JSONSerialization.data(
            withJSONObject: config,
            options: [.prettyPrinted, .sortedKeys]
        )

        // Write to temp file first, then atomic move
        let tempFile = Self.configFile.appendingPathExtension("tmp")
        try data.write(to: tempFile, options: .atomic)

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: Self.configFile.path) {
            try fileManager.removeItem(at: Self.configFile)
        }
        try fileManager.moveItem(at: tempFile, to: Self.configFile)

        // Restrict permissions (owner read/write only)
        try? fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: Self.configFile.path
        )

        // Only update the in-memory key if env var is not set
        if ProcessInfo.processInfo.environment["OPENAI_API_KEY"] == nil {
            self.apiKey = key
        }
    }

    /// Get the current API key (environment variable takes precedence)
    func getApiKey() -> String? {
        // Always check environment first (it may have changed)
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
           !envKey.trimmingCharacters(in: .whitespaces).isEmpty {
            return envKey.trimmingCharacters(in: .whitespaces)
        }
        return apiKey
    }
}

// MARK: - Errors

enum DataStoreError: LocalizedError {
    case emptyApiKey

    var errorDescription: String? {
        switch self {
        case .emptyApiKey:
            return "API key cannot be empty"
        }
    }
}
