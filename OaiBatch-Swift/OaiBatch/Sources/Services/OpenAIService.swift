//
//  OpenAIService.swift
//  OaiBatch
//
//  Actor for OpenAI Batch API interactions.
//

import Foundation

/// Actor for thread-safe OpenAI API calls
actor OpenAIService {

    // MARK: - Configuration

    private let baseURL = URL(string: "https://api.openai.com/v1")!
    private let session: URLSession
    private var apiKey: String

    // MARK: - Initialization

    init(apiKey: String) {
        self.apiKey = apiKey

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    /// Update the API key
    func setApiKey(_ key: String) {
        self.apiKey = key
    }

    // MARK: - Batch Request Creation

    /// Create a new batch request
    func createBatchRequest(
        prompt: String,
        systemPrompt: String,
        maxTokens: Int,
        model: String,
        reasoningEffort: String?
    ) async throws -> BatchRequest {
        let customId = BatchRequest.generateId()

        let normalizedEffort = Config.normalizeReasoningEffort(reasoningEffort)

        var body: [String: Any] = [
            "model": model,
            "instructions": systemPrompt,
            "input": prompt,
            "max_output_tokens": maxTokens
        ]

        if let effort = normalizedEffort, Config.isReasoningModel(model) {
            body["reasoning"] = ["effort": effort]
        }

        let batchRequestLine: [String: Any] = [
            "custom_id": customId,
            "method": "POST",
            "url": Config.BATCH_ENDPOINT,
            "body": body
        ]

        let jsonlData = try JSONSerialization.data(withJSONObject: batchRequestLine)
        guard var jsonlString = String(data: jsonlData, encoding: .utf8) else {
            throw OpenAIError.encodingError
        }
        jsonlString += "\n"

        let fileId = try await uploadFile(content: jsonlString, purpose: "batch")
        let batchResponse = try await createBatch(inputFileId: fileId, endpoint: Config.BATCH_ENDPOINT)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let createdAt = formatter.string(from: Date())

        return BatchRequest(
            id: customId,
            batchId: batchResponse.id,
            fileId: fileId,
            prompt: prompt,
            systemPrompt: systemPrompt,
            model: model,
            reasoningEffort: normalizedEffort,
            maxTokens: maxTokens,
            status: BatchStatus(from: batchResponse.status),
            createdAt: createdAt,
            completedAt: nil,
            inProgressAt: nil,
            outputFileId: batchResponse.outputFileId,
            response: nil,
            usage: nil
        )
    }

    // MARK: - Status Refresh

    /// Refresh statuses for all requests
    func refreshStatuses(requests: [BatchRequest]) async throws -> [BatchRequest] {
        let batches = try await listBatches(limit: 100)

        var batchMap: [String: BatchInfo] = [:]
        for batch in batches {
            batchMap[batch.id] = batch
        }

        var updatedRequests = requests
        for i in updatedRequests.indices {
            let batchId = updatedRequests[i].batchId
            guard !batchId.isEmpty, let batch = batchMap[batchId] else {
                continue
            }

            updatedRequests[i].status = BatchStatus(from: batch.status)
            updatedRequests[i].outputFileId = batch.outputFileId
            updatedRequests[i].completedAt = batch.completedAt
            updatedRequests[i].inProgressAt = batch.inProgressAt
        }

        return updatedRequests
    }

    // MARK: - Response Fetching

    /// Fetch the response for a specific request
    func fetchResponse(for request: BatchRequest) async throws -> (BatchRequest, String) {
        let batchId = request.batchId
        guard !batchId.isEmpty else {
            throw OpenAIError.missingBatchId
        }

        let batch = try await retrieveBatch(batchId: batchId)

        var updatedRequest = request
        updatedRequest.status = BatchStatus(from: batch.status)
        updatedRequest.outputFileId = batch.outputFileId
        updatedRequest.completedAt = batch.completedAt
        updatedRequest.inProgressAt = batch.inProgressAt

        if let cachedResponse = updatedRequest.response {
            return (updatedRequest, cachedResponse)
        }

        guard batch.status == "completed" else {
            throw OpenAIError.batchNotCompleted(status: batch.status)
        }

        guard let outputFileId = batch.outputFileId else {
            throw OpenAIError.noOutputFile
        }

        let outputContent = try await downloadFileContent(fileId: outputFileId)

        let lines = outputContent.components(separatedBy: "\n")
        var responseText: String?
        var usageData: TokenUsage?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            guard let lineData = trimmed.data(using: .utf8),
                  let result = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let resultCustomId = result["custom_id"] as? String,
                  resultCustomId == request.id else {
                continue
            }

            if let response = result["response"] as? [String: Any],
               let body = response["body"] as? [String: Any] {
                responseText = extractTextFromResponsesAPIBody(body)

                if let usage = body["usage"] as? [String: Any] {
                    usageData = TokenUsage(
                        inputTokens: usage["input_tokens"] as? Int ?? 0,
                        outputTokens: usage["output_tokens"] as? Int ?? 0,
                        totalTokens: usage["total_tokens"] as? Int
                    )
                }
            }
            break
        }

        guard let text = responseText else {
            throw OpenAIError.responseNotFound
        }

        updatedRequest.response = text
        updatedRequest.usage = usageData

        return (updatedRequest, text)
    }

    // MARK: - Private API Methods

    /// Upload a file to OpenAI
    private func uploadFile(content: String, purpose: String) async throws -> String {
        let url = baseURL.appendingPathComponent("files")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var bodyData = Data()

        bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
        bodyData.append("Content-Disposition: form-data; name=\"purpose\"\r\n\r\n".data(using: .utf8)!)
        bodyData.append("\(purpose)\r\n".data(using: .utf8)!)

        bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
        bodyData.append("Content-Disposition: form-data; name=\"file\"; filename=\"batch_request.jsonl\"\r\n".data(using: .utf8)!)
        bodyData.append("Content-Type: application/jsonl\r\n\r\n".data(using: .utf8)!)
        bodyData.append(content.data(using: .utf8)!)
        bodyData.append("\r\n".data(using: .utf8)!)

        bodyData.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = bodyData

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fileId = json["id"] as? String else {
            throw OpenAIError.invalidResponse
        }

        return fileId
    }

    /// Create a batch job
    private func createBatch(inputFileId: String, endpoint: String) async throws -> BatchInfo {
        let url = baseURL.appendingPathComponent("batches")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "input_file_id": inputFileId,
            "endpoint": endpoint,
            "completion_window": "24h"
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        return try parseBatchInfo(from: data)
    }

    /// List batches
    private func listBatches(limit: Int) async throws -> [BatchInfo] {
        var components = URLComponents(url: baseURL.appendingPathComponent("batches"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            throw OpenAIError.invalidResponse
        }

        return dataArray.compactMap { parseBatchInfoFromDict($0) }
    }

    /// Retrieve a specific batch
    private func retrieveBatch(batchId: String) async throws -> BatchInfo {
        let url = baseURL.appendingPathComponent("batches").appendingPathComponent(batchId)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        return try parseBatchInfo(from: data)
    }

    /// Download file content
    private func downloadFileContent(fileId: String) async throws -> String {
        let url = baseURL
            .appendingPathComponent("files")
            .appendingPathComponent(fileId)
            .appendingPathComponent("content")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        guard let content = String(data: data, encoding: .utf8) else {
            throw OpenAIError.invalidResponse
        }

        return content
    }

    // MARK: - Helper Methods

    /// Validate HTTP response
    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var errorMessage = "HTTP \(httpResponse.statusCode)"
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                errorMessage = message
            }
            throw OpenAIError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
    }

    /// Parse BatchInfo from JSON data
    private func parseBatchInfo(from data: Data) throws -> BatchInfo {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = parseBatchInfoFromDict(json) else {
            throw OpenAIError.invalidResponse
        }
        return info
    }

    /// Parse BatchInfo from dictionary
    private func parseBatchInfoFromDict(_ dict: [String: Any]) -> BatchInfo? {
        guard let id = dict["id"] as? String,
              let status = dict["status"] as? String else {
            return nil
        }

        return BatchInfo(
            id: id,
            status: status,
            outputFileId: dict["output_file_id"] as? String,
            completedAt: dict["completed_at"] as? TimeInterval,
            inProgressAt: dict["in_progress_at"] as? TimeInterval
        )
    }

    /// Extract text from Responses API body format
    private func extractTextFromResponsesAPIBody(_ body: [String: Any]) -> String {
        if let output = body["output"] as? [[String: Any]] {
            for item in output {
                guard item["type"] as? String == "message",
                      let content = item["content"] as? [[String: Any]] else {
                    continue
                }

                for c in content {
                    if c["type"] as? String == "output_text",
                       let text = c["text"] as? String {
                        return text
                    }
                }
            }
        }

        if let outputText = body["output_text"] as? String {
            return outputText
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: body, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }

        return ""
    }
}

// MARK: - Supporting Types

/// Batch information from OpenAI API
struct BatchInfo {
    let id: String
    let status: String
    let outputFileId: String?
    let completedAt: TimeInterval?
    let inProgressAt: TimeInterval?
}

// MARK: - Errors

enum OpenAIError: LocalizedError {
    case encodingError
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case missingBatchId
    case batchNotCompleted(status: String)
    case noOutputFile
    case responseNotFound

    var errorDescription: String? {
        switch self {
        case .encodingError:
            return "Failed to encode request data"
        case .invalidResponse:
            return "Invalid response from OpenAI API"
        case .apiError(let statusCode, let message):
            return "API Error (\(statusCode)): \(message)"
        case .missingBatchId:
            return "Request is missing batch ID"
        case .batchNotCompleted(let status):
            return "Batch not completed (status: \(status))"
        case .noOutputFile:
            return "Batch completed but no output file available"
        case .responseNotFound:
            return "Could not locate this request's response in the output"
        }
    }
}
