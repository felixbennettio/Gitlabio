import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Small platform helpers so views stay free of UIKit details.

enum Clipboard {
    static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}

enum Haptics {
    static func success() {
        #if canImport(UIKit) && os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    static func warning() {
        #if canImport(UIKit) && os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
    static func tap() {
        #if canImport(UIKit) && os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

extension Image {
    /// Decodes image bytes (PNG, JPEG, GIF, HEIC, …) for previews.
    init?(data: Data) {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        self.init(uiImage: image)
        #else
        guard let image = NSImage(data: data) else { return nil }
        self.init(nsImage: image)
        #endif
    }
}

extension View {
    /// Inline navigation title on iOS.
    func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    func largeTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.large)
        #else
        self
        #endif
    }

    /// Plain technical text input: no autocapitalisation or autocorrection.
    func technicalInput(url: Bool = false) -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(url ? .URL : .asciiCapable)
        #else
        autocorrectionDisabled()
        #endif
    }

    /// Filled rounded box for text fields inside form rows, so stacked fields read as inputs and align.
    func fieldBox() -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Decimal keyboard for number fields on iOS.
    @ViewBuilder
    func numericInput(_ enabled: Bool) -> some View {
        #if os(iOS)
        if enabled { keyboardType(.decimalPad) } else { self }
        #else
        self
        #endif
    }

    func groupedList() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }
}
