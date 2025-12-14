//
//  Theme.swift
//  OaiBatch
//
//  Dark theme styling for OaiBatch macOS app.
//  Matches the Python CustomTkinter GUI color palette.
//

import SwiftUI

// MARK: - Color Extension for Hex Initialization

extension Color {
    /// Initialize a Color from a hex string (e.g., "#0d1117" or "0d1117")
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - App Colors

/// Application color palette matching the Python GUI theme
enum AppColors {
    // Background colors
    static let bgDark = Color(hex: "#0d1117")
    static let bgCard = Color(hex: "#161b22")
    static let bgInput = Color(hex: "#21262d")
    static let bgHover = Color(hex: "#30363d")

    // Border colors
    static let border = Color(hex: "#30363d")
    static let borderFocus = Color(hex: "#58a6ff")

    // Text colors
    static let textPrimary = Color(hex: "#f0f6fc")
    static let textSecondary = Color(hex: "#8b949e")
    static let textMuted = Color(hex: "#6e7681")

    // Accent colors
    static let accent = Color(hex: "#58a6ff")
    static let accentHover = Color(hex: "#79c0ff")

    // Status colors
    static let success = Color(hex: "#3fb950")
    static let warning = Color(hex: "#d29922")
    static let error = Color(hex: "#f85149")
    static let pending = Color(hex: "#8b949e")
}

// MARK: - Status Colors

/// Maps BatchStatus to appropriate colors
enum StatusColors {
    static func color(for status: BatchStatus) -> Color {
        switch status {
        case .completed:
            return AppColors.success
        case .inProgress:
            return AppColors.warning
        case .validating:
            return AppColors.accent
        case .finalizing:
            return AppColors.accent
        case .failed:
            return AppColors.error
        case .expired:
            return AppColors.error
        case .cancelled:
            return AppColors.textMuted
        case .cancelling:
            return AppColors.warning
        case .pending:
            return AppColors.pending
        }
    }

    /// Returns the status color with dark text for badge backgrounds
    static let badgeTextColor = AppColors.bgDark
}

// MARK: - Card Style Modifier

/// Applies card styling: background, rounded corners, and border
struct CardStyle: ViewModifier {
    var cornerRadius: CGFloat = 12
    var borderWidth: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .background(AppColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(AppColors.border, lineWidth: borderWidth)
            )
    }
}

extension View {
    func cardStyle(cornerRadius: CGFloat = 12, borderWidth: CGFloat = 1) -> some View {
        modifier(CardStyle(cornerRadius: cornerRadius, borderWidth: borderWidth))
    }
}

// MARK: - Glow Button Style

/// Primary button style with accent color and hover glow effect
struct GlowButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(AppColors.bgDark)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered || configuration.isPressed ? AppColors.accentHover : AppColors.accent)
            )
            .shadow(
                color: isHovered ? AppColors.accent.opacity(0.4) : Color.clear,
                radius: 8,
                x: 0,
                y: 2
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension View {
    func glowButtonStyle() -> some View {
        self.buttonStyle(GlowButtonStyle())
    }
}

// MARK: - Secondary Button Style

/// Secondary/ghost button style with transparent background and border
struct SecondaryButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .regular))
            .foregroundColor(AppColors.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered || configuration.isPressed ? AppColors.bgHover : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension View {
    func secondaryButtonStyle() -> some View {
        self.buttonStyle(SecondaryButtonStyle())
    }
}

// MARK: - Input Field Style

/// Applies input field styling: background, border, and rounded corners
struct InputFieldStyle: ViewModifier {
    var isFocused: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppColors.bgInput)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isFocused ? AppColors.borderFocus : AppColors.border, lineWidth: 1)
            )
            .foregroundColor(AppColors.textPrimary)
    }
}

extension View {
    func inputFieldStyle(isFocused: Bool = false) -> some View {
        modifier(InputFieldStyle(isFocused: isFocused))
    }
}

// MARK: - Text Field Style for macOS

/// Custom TextField style matching the app theme
struct ThemedTextFieldStyle: TextFieldStyle {
    var isFocused: Bool = false

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppColors.bgInput)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isFocused ? AppColors.borderFocus : AppColors.border, lineWidth: 1)
            )
            .foregroundColor(AppColors.textPrimary)
    }
}

// MARK: - Hover Card Style

/// Card style with hover effect for interactive cards
struct HoverCardStyle: ViewModifier {
    @State private var isHovered = false
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background(AppColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isHovered ? AppColors.accent : AppColors.border, lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension View {
    func hoverCardStyle(cornerRadius: CGFloat = 12) -> some View {
        modifier(HoverCardStyle(cornerRadius: cornerRadius))
    }
}

// MARK: - Preview Support

#if DEBUG
struct Theme_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Color Swatches
            HStack(spacing: 10) {
                colorSwatch(AppColors.bgDark, "bgDark")
                colorSwatch(AppColors.bgCard, "bgCard")
                colorSwatch(AppColors.bgInput, "bgInput")
                colorSwatch(AppColors.accent, "accent")
            }

            // Buttons
            HStack(spacing: 10) {
                Button("Primary Action") {}
                    .buttonStyle(GlowButtonStyle())

                Button("Secondary") {}
                    .buttonStyle(SecondaryButtonStyle())
            }

            // Input Field
            TextField("Placeholder text...", text: .constant(""))
                .textFieldStyle(ThemedTextFieldStyle())
                .frame(width: 300)

            // Card
            VStack(alignment: .leading, spacing: 8) {
                Text("Card Title")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
                Text("Card content goes here")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(16)
            .cardStyle()
            .frame(width: 300)

            // Status Badges
            HStack(spacing: 8) {
                StatusBadgeView(status: .completed)
                StatusBadgeView(status: .inProgress)
                StatusBadgeView(status: .failed)
                StatusBadgeView(status: .pending)
            }
        }
        .padding(40)
        .background(AppColors.bgDark)
        .preferredColorScheme(.dark)
    }

    static func colorSwatch(_ color: Color, _ name: String) -> some View {
        VStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(color)
                .frame(width: 60, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            Text(name)
                .font(.caption2)
                .foregroundColor(AppColors.textMuted)
        }
    }
}
#endif
