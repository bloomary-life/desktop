import SwiftUI
import AppKit

enum AppStyle {
    static let ink = Color(red: 0.067, green: 0.071, blue: 0.059)
    static let muted = ink.opacity(0.58)
    static let paper = Color(red: 0.949, green: 0.941, blue: 0.910)
    static let panel = Color(red: 1.000, green: 0.992, blue: 0.969)
    static let coral = Color(red: 1.000, green: 0.373, blue: 0.239)
    static let lime = Color(red: 0.788, green: 0.973, blue: 0.416)
    static let nsInk = NSColor(red: 0.067, green: 0.071, blue: 0.059, alpha: 1)
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AppStyle.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppStyle.lime.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AppStyle.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppStyle.panel.opacity(configuration.isPressed ? 0.7 : 1))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppStyle.ink.opacity(0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
