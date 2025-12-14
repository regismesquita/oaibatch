//
//  SidebarView.swift
//  OaiBatch
//
//  Navigation sidebar for the macOS app.
//  Matches the Python CustomTkinter GUI sidebar design.
//

import SwiftUI

// MARK: - Navigation Item

/// Navigation destinations for the sidebar
enum NavigationItem: String, CaseIterable, Identifiable, Hashable {
    case create = "New Request"
    case requests = "Requests"
    case settings = "Settings"

    var id: String { rawValue }

    /// SF Symbol icon name for each navigation item
    var icon: String {
        switch self {
        case .create:
            return "plus.circle.fill"
        case .requests:
            return "list.bullet.rectangle.fill"
        case .settings:
            return "gearshape.fill"
        }
    }

    /// Unicode symbol prefix matching the Python GUI style
    var symbolPrefix: String {
        switch self {
        case .create:
            return "\u{2726}"  // Four-pointed star
        case .requests:
            return "\u{25C9}"  // Circle with dot
        case .settings:
            return "\u{2699}"  // Gear
        }
    }
}

// MARK: - Sidebar View

/// Navigation sidebar with app branding and navigation items
struct SidebarView: View {
    @Binding var selection: NavigationItem?
    var isAPIKeyAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Logo/Title Section
            logoSection
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 8)

            // MARK: - Divider
            Rectangle()
                .fill(AppColors.border)
                .frame(height: 1)
                .padding(.horizontal, 16)
                .padding(.vertical, 16)

            // MARK: - Navigation Items
            VStack(spacing: 2) {
                ForEach(NavigationItem.allCases) { item in
                    NavigationButton(
                        item: item,
                        isSelected: selection == item,
                        isEnabled: item == .settings || isAPIKeyAvailable
                    ) {
                        selection = item
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            // MARK: - Model Info
            modelInfoSection
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        }
        .frame(width: 220)
        .background(AppColors.bgCard)
    }

    // MARK: - Logo Section

    private var logoSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("oaibatch")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(AppColors.textPrimary)

            Text("OpenAI Batch API")
                .font(.system(size: 12))
                .foregroundColor(AppColors.textMuted)
        }
    }

    // MARK: - Model Info Section

    private var modelInfoSection: some View {
        HStack {
            Text("Default model: \(Config.DEFAULT_MODEL)")
                .font(.system(size: 11))
                .foregroundColor(AppColors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.bgInput)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Navigation Button

/// Individual navigation button with hover effects
private struct NavigationButton: View {
    let item: NavigationItem
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: {
            if isEnabled {
                action()
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.system(size: 14))
                    .foregroundColor(iconColor)
                    .frame(width: 20)

                Text(item.rawValue)
                    .font(.system(size: 14))
                    .foregroundColor(textColor)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(height: 44)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return AppColors.bgHover
        } else if isHovered && isEnabled {
            return AppColors.bgHover.opacity(0.5)
        }
        return Color.clear
    }

    private var textColor: Color {
        if !isEnabled {
            return AppColors.textMuted
        } else if isSelected {
            return AppColors.textPrimary
        }
        return AppColors.textSecondary
    }

    private var iconColor: Color {
        if !isEnabled {
            return AppColors.textMuted
        } else if isSelected {
            return AppColors.accent
        }
        return AppColors.textSecondary
    }
}

// MARK: - Preview

#if DEBUG
struct SidebarView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // API key available
            SidebarView(
                selection: .constant(.requests),
                isAPIKeyAvailable: true
            )
            .previewDisplayName("API Key Available")

            // API key not available
            SidebarView(
                selection: .constant(.settings),
                isAPIKeyAvailable: false
            )
            .previewDisplayName("API Key Missing")
        }
        .frame(height: 600)
        .background(AppColors.bgDark)
        .preferredColorScheme(.dark)
    }
}
#endif
