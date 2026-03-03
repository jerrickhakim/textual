import Foundation
import Testing

@testable import Textual

extension AttributedStringMarkdownParser {
  @MainActor struct DetailsPreprocessingTests {
    private let parser = AttributedStringMarkdownParser(baseURL: nil)

    @Test func detailsBlockProducesCodeBlockWithCorrectLanguageHint() throws {
      // given
      let markdown = """
        <details>
        <summary>This gets big</summary>
        Lots of text appears here
        </details>
        """

      // when
      let attributed = try parser.attributedString(for: markdown)
      let blocks = attributed.blockRuns()

      // then
      #expect(blocks.count == 1)
      #expect(
        blocks[0].intent?.kind == .codeBlock(languageHint: "_textual_details:This gets big")
      )
    }

    @Test func detailsBlockBodyTextIsPreserved() throws {
      // given
      let markdown = """
        <details>
        <summary>Title</summary>
        Lots of text appears here
        </details>
        """

      // when
      let attributed = try parser.attributedString(for: markdown)
      let blocks = attributed.blockRuns()

      // then
      let block = try #require(blocks.first)
      let body = String(attributed[block.range].characters[...])
        .trimmingCharacters(in: .whitespacesAndNewlines)
      #expect(body == "Lots of text appears here")
    }

    @Test func backtickInSummaryRoundTripsCorrectly() throws {
      // given
      let markdown = """
        <details>
        <summary>Use `code` here</summary>
        Body text
        </details>
        """

      // when
      let attributed = try parser.attributedString(for: markdown)
      let blocks = attributed.blockRuns()

      // Foundation decodes HTML entities in language hints, so &#96; arrives back
      // as a literal backtick in the PresentationIntent. Our extraction formula in
      // BlockContent handles both forms, so verify the full round-trip is correct.
      let hint = try #require(
        {
          if case .codeBlock(let h) = blocks.first?.intent?.kind { return h }
          return nil
        }()
      )
      let prefix = "_textual_details:"
      #expect(hint.hasPrefix(prefix))
      let summary = String(hint.dropFirst(prefix.count))
        .replacing(/&#96;/, with: "`")
      #expect(summary == "Use `code` here")
    }

    @Test func detailsBlockWithNestedCodeBlockIsPreserved() throws {
      // given
      let markdown = """
        <details><summary>Enclosed Code</summary>
        ```
        log output: first line
        log output: second line
        ```
        </details>
        """

      // when
      let attributed = try parser.attributedString(for: markdown)
      let blocks = attributed.blockRuns()

      // then — the whole thing must be a single details block, not fragmented
      #expect(blocks.count == 1)
      let hint = try #require(
        {
          if case .codeBlock(let h) = blocks.first?.intent?.kind { return h }
          return nil
        }()
      )
      #expect(hint == "_textual_details:Enclosed Code")
      let body = String(attributed[blocks[0].range].characters[...])
        .trimmingCharacters(in: .whitespacesAndNewlines)
      #expect(body == "```\nlog output: first line\nlog output: second line\n```")
    }

    @Test func encodedBacktickDecodesBackToBacktick() throws {
      // given — simulate the extraction logic in BlockContent
      let languageHint = "_textual_details:Use &#96;code&#96; here"
      let prefix = "_textual_details:"

      // when
      let summary = String(languageHint.dropFirst(prefix.count))
        .replacing(/&#96;/, with: "`")

      // then
      #expect(summary == "Use `code` here")
    }
  }
}
