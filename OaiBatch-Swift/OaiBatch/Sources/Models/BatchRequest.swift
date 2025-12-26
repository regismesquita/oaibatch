import Foundation

/// Status of a batch request in the OpenAI Batch API
enum BatchStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case validating = "validating"
    case inProgress = "in_progress"
    case finalizing = "finalizing"
    case completed = "completed"
    case failed = "failed"
    case expired = "expired"
    case cancelling = "cancelling"
    case cancelled = "cancelled"

    /// Display name for UI
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .validating: return "Validating"
        case .inProgress: return "In Progress"
        case .finalizing: return "Finalizing"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .expired: return "Expired"
        case .cancelling: return "Cancelling"
        case .cancelled: return "Cancelled"
        }
    }

    /// Whether the status is terminal (no further updates expected)
    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .expired, .cancelled:
            return true
        default:
            return false
        }
    }

    /// Initialize from string, defaulting to pending for unrecognized values
    init(from string: String) {
        self = BatchStatus(rawValue: string) ?? .pending
    }
}

/// Reasoning effort level for reasoning models
enum ReasoningEffort: String, Codable, CaseIterable {
    case none = "none"
    case low = "low"
    case medium = "medium"
    case high = "high"
    case xhigh = "xhigh"

    var displayName: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .xhigh: return "Extra High"
        }
    }
}

/// Token usage information from the API response
struct TokenUsage: Codable, Equatable {
    let inputTokens: Int
    let outputTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }

    init(inputTokens: Int, outputTokens: Int, totalTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens ?? (inputTokens + outputTokens)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        let decodedTotal = try container.decodeIfPresent(Int.self, forKey: .totalTokens)
        totalTokens = decodedTotal ?? (inputTokens + outputTokens)
    }
}

/// A batch request record persisted locally
struct BatchRequest: Codable, Identifiable, Equatable {
    /// Custom request ID (format: "req-{uuid}")
    let id: String

    /// OpenAI Batch ID returned from the API
    var batchId: String

    /// File ID of the uploaded JSONL file
    var fileId: String

    /// User's prompt text
    var prompt: String

    /// System prompt / instructions
    var systemPrompt: String

    /// Model name (e.g., "gpt-5.2-pro")
    var model: String

    /// Reasoning effort level (nil means disabled)
    var reasoningEffort: String?

    /// Maximum output tokens
    var maxTokens: Int

    /// Whether this request enabled the web_search tool
    var webSearchEnabled: Bool

    /// Web search context size (only meaningful when webSearchEnabled == true)
    var webSearchContextSize: String?

    /// Current batch status
    var status: BatchStatus

    /// ISO 8601 timestamp when the request was created locally
    var createdAt: String

    /// Unix timestamp when the batch completed (from API)
    var completedAt: Double?

    /// Unix timestamp when the batch started processing (from API)
    var inProgressAt: Double?

    /// File ID of the output file (available when completed)
    var outputFileId: String?

    /// Cached response text (fetched from output file)
    var response: String?

    /// Token usage information (available when response is fetched)
    var usage: TokenUsage?

    enum CodingKeys: String, CodingKey {
        case id
        case batchId = "batch_id"
        case fileId = "file_id"
        case prompt
        case systemPrompt = "system_prompt"
        case model
        case reasoningEffort = "reasoning_effort"
        case maxTokens = "max_tokens"
        case webSearchEnabled = "web_search_enabled"
        case webSearchContextSize = "web_search_context_size"
        case status
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case inProgressAt = "in_progress_at"
        case outputFileId = "output_file_id"
        case response
        case usage
    }

    init(
        id: String,
        batchId: String,
        fileId: String,
        prompt: String,
        systemPrompt: String,
        model: String,
        reasoningEffort: String?,
        maxTokens: Int,
        webSearchEnabled: Bool = false,
        webSearchContextSize: String? = nil,
        status: BatchStatus,
        createdAt: String,
        completedAt: Double? = nil,
        inProgressAt: Double? = nil,
        outputFileId: String? = nil,
        response: String? = nil,
        usage: TokenUsage? = nil
    ) {
        self.id = id
        self.batchId = batchId
        self.fileId = fileId
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.maxTokens = maxTokens
        self.webSearchEnabled = webSearchEnabled
        self.webSearchContextSize = webSearchContextSize
        self.status = status
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.inProgressAt = inProgressAt
        self.outputFileId = outputFileId
        self.response = response
        self.usage = usage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        batchId = try container.decode(String.self, forKey: .batchId)
        fileId = try container.decode(String.self, forKey: .fileId)
        prompt = try container.decode(String.self, forKey: .prompt)
        systemPrompt = try container.decode(String.self, forKey: .systemPrompt)
        model = try container.decode(String.self, forKey: .model)
        reasoningEffort = try container.decodeIfPresent(String.self, forKey: .reasoningEffort)
        maxTokens = try container.decode(Int.self, forKey: .maxTokens)

        webSearchEnabled = try container.decodeIfPresent(Bool.self, forKey: .webSearchEnabled) ?? false
        webSearchContextSize = try container.decodeIfPresent(String.self, forKey: .webSearchContextSize)

        createdAt = try container.decode(String.self, forKey: .createdAt)
        completedAt = try container.decodeIfPresent(Double.self, forKey: .completedAt)
        inProgressAt = try container.decodeIfPresent(Double.self, forKey: .inProgressAt)
        outputFileId = try container.decodeIfPresent(String.self, forKey: .outputFileId)
        response = try container.decodeIfPresent(String.self, forKey: .response)
        usage = try container.decodeIfPresent(TokenUsage.self, forKey: .usage)

        // Decode status as string and convert to enum
        let statusString = try container.decode(String.self, forKey: .status)
        status = BatchStatus(from: statusString)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(batchId, forKey: .batchId)
        try container.encode(fileId, forKey: .fileId)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(systemPrompt, forKey: .systemPrompt)
        try container.encode(model, forKey: .model)
        try container.encodeIfPresent(reasoningEffort, forKey: .reasoningEffort)
        try container.encode(maxTokens, forKey: .maxTokens)

        try container.encode(webSearchEnabled, forKey: .webSearchEnabled)
        try container.encodeIfPresent(webSearchContextSize, forKey: .webSearchContextSize)

        try container.encode(status.rawValue, forKey: .status)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(inProgressAt, forKey: .inProgressAt)
        try container.encodeIfPresent(outputFileId, forKey: .outputFileId)
        try container.encodeIfPresent(response, forKey: .response)
        try container.encodeIfPresent(usage, forKey: .usage)
    }
}

// MARK: - Formatting Helpers

extension BatchRequest {
    /// Formatted creation date for display
    var formattedCreatedAt: String {
        let trimmed = String(createdAt.prefix(19)).replacingOccurrences(of: "T", with: " ")
        return trimmed.isEmpty ? "-" : trimmed
    }

    /// Formatted completion date for display
    var formattedCompletedAt: String {
        guard let timestamp = completedAt else { return "-" }
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    /// Formatted usage string for display
    var formattedUsage: String {
        guard let usage = usage else { return "-" }

        let inputStr = formatNumber(usage.inputTokens)
        let outputStr = formatNumber(usage.outputTokens)
        let totalStr = formatNumber(usage.totalTokens)

        if let cost = Config.estimateCost(from: usage, model: model) {
            return "\(inputStr) in + \(outputStr) out = \(totalStr) tokens ($\(String(format: "%.2f", cost.total)))"
        }

        return "\(inputStr) in + \(outputStr) out = \(totalStr) tokens"
    }

    /// Prompt preview (truncated for list display)
    var promptPreview: String {
        let cleaned = prompt.replacingOccurrences(of: "\n", with: " ")
        if cleaned.count > 120 {
            return String(cleaned.prefix(120)) + "..."
        }
        return cleaned
    }

    /// Truncated batch ID for display
    var truncatedBatchId: String {
        if batchId.count > 30 {
            return String(batchId.prefix(30)) + "..."
        }
        return batchId
    }

    /// Display string for reasoning effort
    var reasoningEffortDisplay: String {
        reasoningEffort ?? "none"
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? String(n)
    }
}

// MARK: - Factory

extension BatchRequest {
    /// Generate a new request ID
    static func generateId() -> String {
        let uuid = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        return "req-\(String(uuid.prefix(8)))"
    }

    /// Create a new batch request with current timestamp
    static func create(
        batchId: String,
        fileId: String,
        prompt: String,
        systemPrompt: String,
        model: String,
        reasoningEffort: String?,
        maxTokens: Int,
        status: BatchStatus
    ) -> BatchRequest {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let createdAt = formatter.string(from: Date())

        return BatchRequest(
            id: generateId(),
            batchId: batchId,
            fileId: fileId,
            prompt: prompt,
            systemPrompt: systemPrompt,
            model: model,
            reasoningEffort: Config.normalizeReasoningEffort(reasoningEffort),
            maxTokens: maxTokens,
            status: status,
            createdAt: createdAt
        )
    }
}
