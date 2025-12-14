import Foundation

/// Token pricing for a model (per 1M tokens)
struct ModelPricing: Equatable {
    let inputPer1M: Double
    let outputPer1M: Double

    init(inputPer1M: Double, outputPer1M: Double) {
        self.inputPer1M = inputPer1M
        self.outputPer1M = outputPer1M
    }
}

/// Cost breakdown from token usage
struct CostEstimate: Equatable {
    let input: Double
    let output: Double
    let total: Double
}

/// Configuration constants and utilities for OaiBatch
enum Config {
    // MARK: - Model Configuration

    /// Supported models and their Batch API token pricing (per 1M tokens)
    static let MODEL_PRICING: [String: ModelPricing] = [
        "gpt-5.2": ModelPricing(inputPer1M: 0.875, outputPer1M: 7.00),
        "gpt-5.2-pro": ModelPricing(inputPer1M: 10.50, outputPer1M: 84.00),
        "o3-pro": ModelPricing(inputPer1M: 10.00, outputPer1M: 40.00),
        "o3": ModelPricing(inputPer1M: 5.00, outputPer1M: 20.00),
        "o4-mini": ModelPricing(inputPer1M: 0.55, outputPer1M: 2.20),
    ]

    /// Default model for new requests
    static let DEFAULT_MODEL = "gpt-5.2-pro"

    /// List of available models sorted alphabetically
    static var availableModels: [String] {
        MODEL_PRICING.keys.sorted()
    }

    /// Models that support reasoning effort
    static let reasoningModels: Set<String> = ["o3", "o3-pro", "o4-mini"]

    // MARK: - Reasoning Configuration

    /// Available reasoning effort levels
    static let REASONING_EFFORT_CHOICES = ["none", "low", "medium", "high", "xhigh"]

    /// Default reasoning effort for new requests
    static let DEFAULT_REASONING_EFFORT = "xhigh"

    // MARK: - API Configuration

    /// Default maximum output tokens
    static let DEFAULT_MAX_TOKENS = 100_000

    /// Batch API endpoint
    static let BATCH_ENDPOINT = "/v1/responses"

    /// Batch completion window
    static let COMPLETION_WINDOW = "24h"

    // MARK: - Storage Configuration

    /// Directory for storing oaibatch data
    static var dataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".oaibatch")
    }

    /// Path to requests JSON file
    static var requestsFile: URL {
        dataDirectory.appendingPathComponent("requests.json")
    }

    /// Path to config JSON file (for API key)
    static var configFile: URL {
        dataDirectory.appendingPathComponent("config.json")
    }

    // MARK: - Model Helpers

    /// Check if a model supports reasoning effort
    static func isReasoningModel(_ model: String) -> Bool {
        reasoningModels.contains(model)
    }

    // MARK: - Reasoning Effort Normalization

    /// Normalize a user-provided reasoning effort string.
    static func normalizeReasoningEffort(_ effort: String?) -> String? {
        guard let effort = effort else { return nil }

        let value = effort.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let disableValues = ["", "none", "off", "false", "0", "disable", "disabled"]
        if disableValues.contains(value) {
            return nil
        }

        return value
    }

    /// Check if a reasoning effort value is valid
    static func isValidReasoningEffort(_ effort: String?) -> Bool {
        guard let effort = effort else { return true }
        let normalized = normalizeReasoningEffort(effort)
        if normalized == nil { return true }
        return REASONING_EFFORT_CHOICES.contains(normalized!)
    }

    // MARK: - Cost Estimation

    /// Estimate cost in USD from token usage for a given model
    static func estimateCost(from usage: TokenUsage, model: String) -> CostEstimate? {
        guard let pricing = MODEL_PRICING[model] else { return nil }

        let inputCost = (Double(usage.inputTokens) / 1_000_000.0) * pricing.inputPer1M
        let outputCost = (Double(usage.outputTokens) / 1_000_000.0) * pricing.outputPer1M
        let totalCost = inputCost + outputCost

        return CostEstimate(input: inputCost, output: outputCost, total: totalCost)
    }

    /// Get pricing info for a model
    static func pricing(for model: String) -> ModelPricing? {
        MODEL_PRICING[model]
    }

    /// Format pricing for display
    static func formattedPricing(for model: String) -> String {
        guard let pricing = MODEL_PRICING[model] else {
            return "Pricing: unknown"
        }

        let inputStr = pricing.inputPer1M < 1
            ? String(format: "%.3f", pricing.inputPer1M)
            : String(format: "%.2f", pricing.inputPer1M)
        let outputStr = pricing.outputPer1M < 1
            ? String(format: "%.3f", pricing.outputPer1M)
            : String(format: "%.2f", pricing.outputPer1M)

        return "Pricing: $\(inputStr) in / $\(outputStr) out per 1M tokens"
    }
}
