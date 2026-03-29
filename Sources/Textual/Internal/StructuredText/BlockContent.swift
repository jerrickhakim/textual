import SwiftUI

extension StructuredText {
  struct BlockContent<Content: AttributedStringProtocol>: View {
    @Environment(\.chatComponentRenderer) private var chatRenderer

    private let parent: PresentationIntent.IntentType?
    private let content: Content
    private let useLazyLayout: Bool

    init(parent: PresentationIntent.IntentType? = nil, content: Content, useLazyLayout: Bool = false) {
      self.parent = parent
      self.content = content
      self.useLazyLayout = useLazyLayout
    }

    var body: some View {
      let runs = content.blockRuns(parent: parent)
      let identified = StableBlockRun.from(runs: runs, content: content)

      let useLazy = useLazyLayout || chatRenderer != nil

      if useLazy {
        LazyVStack(alignment: .leading, spacing: 12) {
          ForEach(identified) { item in
            let substring = content[item.run.range]

            if let component = substring.runs.first(where: { $0[ChatComponentKey.self] != nil })?[ChatComponentKey.self] {
              ChatComponentView(data: component)
            } else {
              FrozenBlock(contentHash: item.id, intent: item.run.intent, content: substring)
            }
          }
        }
      } else {
        // BlockVStack relies on BlockSpacingKey preferences emitted by each
        // block's style. FrozenBlock's Equatable conformance suppresses body
        // evaluation (and therefore preference emission) for unchanged blocks,
        // so we use Block directly here to keep spacing working.
        BlockVStack {
          ForEach(identified) { item in
            Block(intent: item.run.intent, content: content[item.run.range])
          }
        }
      }
    }
  }

}

// MARK: - Frozen Block
//
// Equatable wrapper around Block. SwiftUI compares FrozenBlock instances by
// contentHash alone. When the hash hasn't changed (i.e. the block's text and
// intent are identical), SwiftUI skips body evaluation entirely — no layout,
// no text shaping, no syntax highlighting for that block.

private struct FrozenBlock: View, Equatable {
  let contentHash: Int
  let intent: PresentationIntent.IntentType?
  let content: AttributedSubstring

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.contentHash == rhs.contentHash
  }

  var body: some View {
    StructuredText.Block(intent: intent, content: content)
  }
}

// MARK: - Stable Block Identity
//
// Wraps each BlockRun with a content-hash-based ID so SwiftUI can skip
// re-rendering unchanged blocks during streaming updates. Only the last
// (actively streaming) block gets a new ID; earlier blocks keep theirs.

private struct StableBlockRun: Identifiable {
  let id: Int
  let run: AttributedString.BlockRuns.BlockRun

  static func from(
    runs: AttributedString.BlockRuns,
    content: some AttributedStringProtocol
  ) -> [StableBlockRun] {
    runs.enumerated().map { index, run in
      let text = String(content[run.range].characters)
      var hasher = Hasher()
      hasher.combine(index)
      hasher.combine(String(describing: run.intent))
      hasher.combine(text)
      return StableBlockRun(id: hasher.finalize(), run: run)
    }
  }
}

extension StructuredText {
  struct Block: View {
    private let intent: PresentationIntent.IntentType?
    private let content: AttributedSubstring

    init(intent: PresentationIntent.IntentType?, content: AttributedSubstring) {
      self.intent = intent
      self.content = content
    }

    var body: some View {
      switch intent?.kind {
      case .paragraph where content.isMathBlock:
        MathBlock(content)
      case .paragraph:
        Paragraph(content)
      case .header(let level):
        Heading(content, level: level)
      case .orderedList:
        OrderedList(intent: intent, content: content)
      case .unorderedList:
        UnorderedList(intent: intent, content: content)
      case .codeBlock(let languageHint) where languageHint?.hasPrefix("_textual_details:") ?? false:
        DetailsBlock(
          content,
          summary: String((languageHint ?? "").dropFirst("_textual_details:".count))
            .replacing(/&#96;/, with: "`")
        )
      case .codeBlock(let languageHint) where languageHint?.lowercased() == "math":
        MathCodeBlock(content)
      case .codeBlock(let languageHint):
        CodeBlock(content, languageHint: languageHint)
      case .blockQuote:
        BlockQuote(intent: intent, content: content)
      case .thematicBreak:
        ThematicBreak(content)
      case .table(let columns):
        Table(intent: intent, content: content, columns: columns)
      default:
        Paragraph(content)
      }
    }
  }
}
