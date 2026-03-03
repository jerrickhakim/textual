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
  //
  // The opening fence is made one backtick longer than the longest consecutive
  // backtick run in the body, so a body that itself contains fenced code blocks
  // never prematurely closes the outer fence.
  private func preprocessDetails(_ input: String) -> String {
    input.replacing(
      /(?s)<details>\s*<summary>(.*?)<\/summary>(.*?)<\/details>/
    ) { match in
      let summary = match.output.1.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacing(/`/, with: "&#96;")
      let body = match.output.2.trimmingCharacters(in: .whitespacesAndNewlines)
      let fence = String(repeating: "`", count: longestBacktickRun(in: body) + 1)
      return "\(fence)_textual_details:\(summary)\n\(body)\n\(fence)"
    }
  }

  // Returns the length of the longest consecutive run of backticks in `string`,
  // with a minimum of 2 so that adding 1 always produces a valid 3-backtick fence.
  private func longestBacktickRun(in string: String) -> Int {
    var maxRun = 2
    var currentRun = 0
    for char in string {
      if char == "`" {
        currentRun += 1
        maxRun = max(maxRun, currentRun)
      } else {
        currentRun = 0
      }
    }
    return maxRun
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
