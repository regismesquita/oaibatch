//
//  StatusBadge.swift
//  OaiBatch
//
//  Status badge component for batch request status.
//

import SwiftUI

struct StatusBadgeView: View {
    let status: BatchStatus

    private var statusColor: Color {
        switch status {
        case .completed:
            return AppColors.success
        case .inProgress, .finalizing:
            return AppColors.warning
        case .validating, .pending:
            return AppColors.accent
        case .failed, .expired:
            return AppColors.error
        case .cancelled, .cancelling:
            return AppColors.textMuted
        }
    }

    var body: some View {
        Text(status.displayName.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(AppColors.bgDark)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(statusColor)
            )
    }
}

#Preview {
    VStack(spacing: 8) {
        ForEach(BatchStatus.allCases, id: \.self) { status in
            HStack {
                Text(status.rawValue)
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.textSecondary)
                    .frame(width: 100, alignment: .leading)
                StatusBadgeView(status: status)
            }
        }
    }
    .padding(24)
    .background(AppColors.bgDark)
}
