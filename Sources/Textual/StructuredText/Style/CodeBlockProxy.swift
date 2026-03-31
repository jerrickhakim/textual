import SwiftUI
import UniformTypeIdentifiers

extension StructuredText {
  /// A proxy for a rendered code block that custom code block styles can use.
  public struct CodeBlockProxy {
    private let content: AttributedSubstring
    /// Raw code string for direct code block rendering (avoids attributed string round-trip).
    private let rawCode: String?

    internal init(_ content: AttributedSubstring) {
      self.content = content
      self.rawCode = nil
    }

    /// Creates a proxy from a raw code string (used by DirectCodeBlock).
    internal init(code: String) {
      let attributed = AttributedString(code)
      self.content = attributed[attributed.startIndex..<attributed.endIndex]
      self.rawCode = code
    }

    /// Copies the code block contents to the system pasteboard.
    ///
    /// Textual writes both a plain-text and an HTML representation when possible.
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    public func copyToPasteboard() {
      #if TEXTUAL_ENABLE_TEXT_SELECTION && canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let formatter = Formatter(AttributedString(content))
        pasteboard.setString(formatter.plainText(), forType: .string)
        pasteboard.setString(formatter.html(), forType: .html)
      #elseif TEXTUAL_ENABLE_TEXT_SELECTION && canImport(UIKit)
        let formatter = Formatter(AttributedString(content))
        UIPasteboard.general.setItems(
          [
            [
              UTType.plainText.identifier: formatter.plainText(),
              UTType.html.identifier: formatter.html(),
            ]
          ]
        )
      #endif
    }
  }
}
