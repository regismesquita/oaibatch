//
//  RequestCard.swift
//  OaiBatch
//
//  Card component for displaying a batch request in the list.
//  Shows request ID, status badge, batch ID, prompt preview, and timestamps.
//

import SwiftUI

struct RequestCard: View {
    let request: BatchRequest
    var onClick: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top Row: Request ID (monospace, accent color) and Status Badge
            HStack(alignment: .center) {
                Text(request.id)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(AppColors.accent)

                Spacer()

                StatusBadgeView(status: request.status)
            }

            // Truncated Batch ID
            Text(request.truncatedBatchId)
                .font(.system(size: 11))
                .foregroundColor(AppColors.textMuted)
                .padding(.top, 2)

            // Prompt Preview (first 120 characters)
            Text(request.promptPreview)
                .font(.system(size: 12))
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(2)
                .padding(.top, 4)

            // Bottom Row: Created and Completed timestamps
            HStack {
                // Created timestamp
                HStack(spacing: 4) {
                    Text("Created:")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textMuted)
                    Text(request.formattedCreatedAt)
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textMuted)
                }

                Spacer()

                // Completed timestamp (only shown if completed)
                if request.completedAt != nil {
                    HStack(spacing: 4) {
                        Text("Completed:")
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.success)
                        Text(request.formattedCompletedAt)
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.success)
                    }
                }
            }
            .padding(.top, 6)
        }
        .padding(16)
        .background(AppColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? AppColors.accent : AppColors.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onClick?()
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        // Completed request with completed timestamp
        RequestCard(
            request: BatchRequest(
                id: "req-12345678",
                batchId: "batch_abc123def456ghi789jkl012mno345",
                fileId: "file_xyz",
                prompt: "Write a comprehensive analysis of the current state of artificial intelligence and its impact on various industries including healthcare, finance, and education.",
                systemPrompt: "You are helpful.",
                model: "gpt-5.2-pro",
                reasoningEffort: nil,
                maxTokens: 100000,
                status: .completed,
                createdAt: "2024-01-15T10:30:00",
                completedAt: 1705325400 // 2024-01-15 12:30:00
            ),
            onClick: { print("Clicked completed request") }
        )

        // In-progress request (no completed timestamp)
        RequestCard(
            request: BatchRequest(
                id: "req-87654321",
                batchId: "batch_def456ghi789jkl012mno345pqr678",
                fileId: "file_abc",
                prompt: "Explain quantum computing in simple terms.",
                systemPrompt: "You are helpful.",
                model: "o3",
                reasoningEffort: "high",
                maxTokens: 50000,
                status: .inProgress,
                createdAt: "2024-01-15T11:45:00"
            ),
            onClick: { print("Clicked in-progress request") }
        )

        // Failed request
        RequestCard(
            request: BatchRequest(
                id: "req-11111111",
                batchId: "batch_ghi789",
                fileId: "file_def",
                prompt: "Generate a Python script for data analysis.",
                systemPrompt: "You are a coding assistant.",
                model: "gpt-5.2",
                reasoningEffort: nil,
                maxTokens: 80000,
                status: .failed,
                createdAt: "2024-01-15T09:00:00"
            )
        )
    }
    .padding(24)
    .background(AppColors.bgDark)
}
