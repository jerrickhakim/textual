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
        DisclosureGroup(isExpanded: $isExpanded) {
          StructuredText(markdown: bodyMarkdown)
        } label: {
          InlineText(markdown: summary)
        }
        // Register this view's frame as an exclusion rect so the text-selection
        // overlay (NSTextInteractionView / UIKitTextInteractionOverlay) passes
        // pointer events through to the DisclosureGroup toggle rather than
        // consuming them. This is the same mechanism used by Overflow for
        // scrollable code blocks and tables.
        .background(
          GeometryReader { geometry in
            Color.clear
              .preference(
                key: OverflowFrameKey.self,
                value: [geometry.frame(in: .textContainer)]
              )
          }
        )
      #endif
    }
  }
}
