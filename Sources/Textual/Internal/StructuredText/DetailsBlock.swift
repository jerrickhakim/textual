import SwiftUI

extension StructuredText {
  struct DetailsBlock: View {
    private let summary: String
    private let bodyMarkdown: String

    #if !os(watchOS) && !os(tvOS)
      @State private var isExpanded = false
    #endif

    init(_ content: AttributedSubstring, summary: String) {
      self.summary = summary
      // Strip the trailing newline that Foundation appends to code block content.
      var body = String(content.characters[...])
      if body.hasSuffix("\n") {
        body = String(body.dropLast())
      }
      self.bodyMarkdown = body
    }

    var body: some View {
      #if os(watchOS) || os(tvOS)
        VStack(alignment: .leading) {
          InlineText(markdown: summary)
          StructuredText(markdown: bodyMarkdown)
        }
      #else
        VStack(alignment: .leading, spacing: 0) {
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            // Only the toggle button's frame is registered as a text-selection
            // exclusion rect.  This lets the overlay pass pointer events through
            // to the button while leaving the summary InlineText in normal
            // selection territory.
            Button {
              withAnimation { isExpanded.toggle() }
            } label: {
              SwiftUI.Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .imageScale(.small)
            }
            .buttonStyle(.plain)
            .textual.interactiveRegion()

            InlineText(markdown: summary)
          }

          if isExpanded {
            StructuredText(markdown: bodyMarkdown)
          }
        }
      #endif
    }
  }
}
