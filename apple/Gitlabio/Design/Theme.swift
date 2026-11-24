import SwiftUI
import GitLabCore

enum Theme {
    static let orange = Color(hex: "#FC6D26")
    static let tangerine = Color(hex: "#FCA326")
    static let coral = Color(hex: "#E24329")
    static let purple = Color(hex: "#7B58CF")
    static let indigo = Color(hex: "#4B4BD8")
    static let mint = Color(hex: "#2DA160")

    static let brandGradient = LinearGradient(colors: [orange, coral, purple], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let warmGradient = LinearGradient(colors: [tangerine, orange], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let merged = Color(hex: "#7B58CF")
    static let opened = Color(hex: "#2DA160")
    static let closed = Color(hex: "#DD2B0E")

    static func color(for status: CIStatus) -> Color {
        switch status {
        case .success: return Color(hex: "#2DA160")
        case .failed: return Color(hex: "#E5484D")
        case .running: return Color(hex: "#3B82F6")
        case .pending, .waitingForResource, .preparing, .created: return Color(hex: "#F5A524")
        case .manual, .scheduled: return Color(hex: "#8B5CF6")
        case .canceled, .canceling, .skipped, .unknown: return .secondary
        }
    }

    static func symbol(for status: CIStatus) -> String {
        switch status {
        case .success: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .running: return "circle.dotted.circle"
        case .pending, .waitingForResource, .preparing: return "clock.fill"
        case .created: return "circle.dashed"
        case .manual: return "play.circle.fill"
        case .scheduled: return "calendar.circle.fill"
        case .canceled, .canceling: return "slash.circle.fill"
        case .skipped: return "chevron.forward.2"
        case .unknown: return "questionmark.circle"
        }
    }

    /// Code colours tuned for both light and dark backgrounds.
    static func color(for kind: SyntaxHighlighter.Kind, dark: Bool) -> Color {
        switch kind {
        case .plain, .punctuation: return .primary
        case .keyword: return dark ? Color(hex: "#FF7AB2") : Color(hex: "#AD3DA4")
        case .string: return dark ? Color(hex: "#FF8170") : Color(hex: "#C41A16")
        case .comment: return dark ? Color(hex: "#7F8C98") : Color(hex: "#5D6C79")
        case .number: return dark ? Color(hex: "#D9C97C") : Color(hex: "#272AD8")
        case .type: return dark ? Color(hex: "#5DD8FF") : Color(hex: "#0B4F79")
        case .attribute: return dark ? Color(hex: "#FFA14F") : Color(hex: "#815F03")
        case .function: return dark ? Color(hex: "#67B7A4") : Color(hex: "#326D74")
        }
    }

    /// The 16 standard terminal colours plus the xterm 256-colour cube for CI logs.
    static func terminal(_ index: Int) -> Color {
        let basic: [String] = ["#3B4048", "#F87171", "#4ADE80", "#FACC15", "#60A5FA", "#E879F9", "#22D3EE", "#E5E7EB",
                               "#6B7280", "#FCA5A5", "#86EFAC", "#FDE68A", "#93C5FD", "#F0ABFC", "#67E8F9", "#FFFFFF"]
        if index < 16 { return Color(hex: basic[max(0, index)]) }
        if index < 232 {
            let value = index - 16
            let steps: [Double] = [0, 95, 135, 175, 215, 255]
            return Color(red: steps[value / 36] / 255, green: steps[(value / 6) % 6] / 255, blue: steps[value % 6] / 255)
        }
        let gray = Double(8 + (index - 232) * 10) / 255
        return Color(red: gray, green: gray, blue: gray)
    }
}

extension Color {
    init(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        let value = UInt64(text, radix: 16) ?? 0x888888
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    /// A stable colour derived from a string, for avatars and project tiles without images.
    static func seeded(_ seed: String) -> Color {
        let palette: [String] = ["#FC6D26", "#7B58CF", "#2DA160", "#3B82F6", "#E24329", "#DB2777", "#0EA5E9", "#F59E0B", "#14B8A6", "#6366F1"]
        let hash = seed.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        return Color(hex: palette[abs(hash) % palette.count])
    }
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
