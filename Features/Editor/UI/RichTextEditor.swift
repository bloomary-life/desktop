import SwiftUI
import AppKit

enum EditorFormatCommand {
    case bold
    case italic
    case strikethrough
    case underline
    case code
    case clear
    case bullets
    case numbered
    case insert(String)
}

struct RichTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var command: EditorFormatCommand?
    var onFirstEdit: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onFirstEdit: onFirstEdit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.textColor = AppStyle.nsInk
        textView.font = .preferredFont(forTextStyle: .body)
        textView.focusRingType = .none
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = .zero
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.string = text
        textView.typingAttributes = context.coordinator.defaultTypingAttributes
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            textView.string = text
        }

        guard let command else { return }
        context.coordinator.isApplyingCommand = true
        context.coordinator.apply(command, to: textView)
        context.coordinator.isApplyingCommand = false
        DispatchQueue.main.async {
            self.command = nil
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        private let onFirstEdit: () -> Void
        var isApplyingCommand = false
        private var didTrackFirstEdit = false

        let defaultTypingAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: AppStyle.nsInk
        ]

        init(text: Binding<String>, onFirstEdit: @escaping () -> Void) {
            _text = text
            self.onFirstEdit = onFirstEdit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            trackFirstEdit()
            publish(textView.string)
        }

        func apply(_ command: EditorFormatCommand, to textView: NSTextView) {
            switch command {
            case .bold:
                replaceSelection(in: textView) { Self.boldText($0) }
            case .italic:
                replaceSelection(in: textView) { Self.italicText($0) }
            case .strikethrough:
                replaceSelection(in: textView) { Self.combine($0, mark: "\u{0336}") }
            case .underline:
                replaceSelection(in: textView) { Self.combine($0, mark: "\u{0332}") }
            case .code:
                replaceSelection(in: textView) { "`\($0)`" }
            case .clear:
                replaceSelection(in: textView) { Self.plainText($0) }
            case .bullets:
                prefixSelectedLines(in: textView) { _ in "- " }
            case .numbered:
                prefixSelectedLines(in: textView) { "\($0 + 1). " }
            case .insert(let value):
                let selectedRange = textView.selectedRange()
                textView.textStorage?.replaceCharacters(in: selectedRange, with: value)
                textView.setSelectedRange(NSRange(location: selectedRange.location + (value as NSString).length, length: 0))
                trackFirstEdit()
                publish(textView.string)
            }
        }

        private func replaceSelection(in textView: NSTextView, transform: (String) -> String) {
            let selectedRange = textView.selectedRange()
            guard selectedRange.length > 0 else { return }
            let selectedText = (textView.string as NSString).substring(with: selectedRange)
            let replacement = transform(selectedText)
            textView.textStorage?.beginEditing()
            textView.textStorage?.replaceCharacters(in: selectedRange, with: replacement)
            textView.textStorage?.endEditing()
            textView.setSelectedRange(NSRange(location: selectedRange.location, length: (replacement as NSString).length))
            publish(textView.string)
        }

        private func prefixSelectedLines(in textView: NSTextView, prefix: (Int) -> String) {
            replaceSelectedLines(in: textView) { lines in
                lines.enumerated().map { prefix($0.offset) + $0.element }.joined(separator: "\n")
            }
        }

        private func removeSelectedLinePrefix(in textView: NSTextView) {
            replaceSelectedLines(in: textView) { lines in
                lines.map { line in
                    if line.hasPrefix("\t") { return String(line.dropFirst()) }
                    if line.hasPrefix("- ") { return String(line.dropFirst(2)) }
                    return line.replacingOccurrences(of: #"^\d+\. "#, with: "", options: .regularExpression)
                }
                .joined(separator: "\n")
            }
        }

        private func replaceSelectedLines(in textView: NSTextView, transform: ([String]) -> String) {
            let nsText = textView.string as NSString
            let selectedRange = textView.selectedRange()
            let lineRange = nsText.lineRange(for: selectedRange)
            let replacement = transform(nsText.substring(with: lineRange).split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
            textView.textStorage?.beginEditing()
            textView.textStorage?.replaceCharacters(in: lineRange, with: replacement)
            textView.textStorage?.endEditing()
            textView.setSelectedRange(NSRange(location: lineRange.location, length: (replacement as NSString).length))
            publish(textView.string)
        }

        private func publish(_ value: String) {
            if isApplyingCommand {
                DispatchQueue.main.async {
                    self.text = value
                }
            } else {
                text = value
            }
        }

        private func trackFirstEdit() {
            guard !didTrackFirstEdit else { return }
            didTrackFirstEdit = true
            onFirstEdit()
        }

        private static func boldText(_ value: String) -> String {
            transform(value, lowerOffset: 0x1D5EE, upperOffset: 0x1D5D4, digitOffset: 0x1D7EC)
        }

        private static func italicText(_ value: String) -> String {
            transform(value, lowerOffset: 0x1D622, upperOffset: 0x1D608, digitOffset: nil)
        }

        private static func transform(_ value: String, lowerOffset: Int, upperOffset: Int, digitOffset: Int?) -> String {
            String(value.unicodeScalars.map { scalar in
                let code = Int(scalar.value)
                if (65...90).contains(code), let mapped = UnicodeScalar(upperOffset + code - 65) {
                    return Character(mapped)
                }
                if (97...122).contains(code), let mapped = UnicodeScalar(lowerOffset + code - 97) {
                    return Character(mapped)
                }
                if let digitOffset, (48...57).contains(code), let mapped = UnicodeScalar(digitOffset + code - 48) {
                    return Character(mapped)
                }
                return Character(scalar)
            })
        }

        private static func combine(_ value: String, mark: Character) -> String {
            value.flatMap { [$0, mark] }.map(String.init).joined()
        }

        private static func plainText(_ value: String) -> String {
            let stripped = value.replacingOccurrences(of: "`", with: "")
            return stripped.decomposedStringWithCanonicalMapping
                .unicodeScalars
                .compactMap { scalar -> String? in
                    if scalar.value == 0x0332 || scalar.value == 0x0336 { return nil }
                    return String(plainScalar(scalar) ?? scalar)
                }
                .joined()
        }

        private static func plainScalar(_ scalar: UnicodeScalar) -> UnicodeScalar? {
            let code = Int(scalar.value)
            switch code {
            case 0x1D5D4...0x1D5ED:
                return UnicodeScalar(65 + code - 0x1D5D4)
            case 0x1D5EE...0x1D607:
                return UnicodeScalar(97 + code - 0x1D5EE)
            case 0x1D7EC...0x1D7F5:
                return UnicodeScalar(48 + code - 0x1D7EC)
            case 0x1D608...0x1D621:
                return UnicodeScalar(65 + code - 0x1D608)
            case 0x1D622...0x1D63B:
                return UnicodeScalar(97 + code - 0x1D622)
            default:
                return nil
            }
        }
    }
}
