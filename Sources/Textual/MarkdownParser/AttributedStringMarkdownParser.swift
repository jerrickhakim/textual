import Foundation

/// A ``MarkupParser`` implementation backed by Foundation’s Markdown support.
///
/// This parser leverages Foundation’s Markdown support and preserves structure via
/// presentation intents.
///
/// This parser can process its output to expand custom emoji and math expressions into
/// inline attachments.
public struct AttributedStringMarkdownParser: MarkupParser {
  private let baseURL: URL?
  private let options: AttributedString.MarkdownParsingOptions
  private let processor: PatternProcessor

  public init(
    baseURL: URL?,
    options: AttributedString.MarkdownParsingOptions = .init(),
    syntaxExtensions: [SyntaxExtension] = []
  ) {
    self.baseURL = baseURL
    self.options = options
    self.processor = PatternProcessor(syntaxExtensions: syntaxExtensions)
  }

  public func attributedString(for input: String) throws -> AttributedString {
    try processor.expand(
      AttributedString(
        markdown: preprocessDetails(input),
        including: \.textual,
        options: options,
        baseURL: baseURL
      )
    )
  }

  // Transforms <details>/<summary> HTML blocks into fenced code blocks with a
  // `_textual_details:Summary` language hint so Foundation's markdown parser can
  // represent them as a known PresentationIntent that the rendering layer picks up.
  private func preprocessDetails(_ input: String) -> String {
    input.replacing(
      /(?s)<details>\s*<summary>(.*?)<\/summary>(.*?)<\/details>/
    ) { match in
      let summary = match.output.1.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacing(/`/, with: "&#96;")
      let body = match.output.2.trimmingCharacters(in: .whitespacesAndNewlines)
      return "```_textual_details:\(summary)\n\(body)\n```"
    }
  }
}

extension MarkupParser where Self == AttributedStringMarkdownParser {
  /// Creates a Markdown parser configured for inline-only syntax.
  public static func inlineMarkdown(
    baseURL: URL? = nil,
    syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] = []
  ) -> Self {
    .init(
      baseURL: baseURL,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace),
      syntaxExtensions: syntaxExtensions
    )
  }

  /// Creates a Markdown parser configured for full-document syntax.
  public static func markdown(
    baseURL: URL? = nil,
    syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] = []
  ) -> Self {
    .init(
      baseURL: baseURL,
      syntaxExtensions: syntaxExtensions
    )
  }
}
