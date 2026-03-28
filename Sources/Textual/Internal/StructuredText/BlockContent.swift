import SwiftUI

extension StructuredText {
  struct BlockContent<Content: AttributedStringProtocol>: View {
    private let parent: PresentationIntent.IntentType?
    private let content: Content

    init(parent: PresentationIntent.IntentType? = nil, content: Content) {
      self.parent = parent
      self.content = content
    }

    var body: some View {
      let runs = content.blockRuns(parent: parent)

      // Compute stable content-hash IDs so unchanged blocks skip re-render.
      var hashCounts: [Int: Int] = [:]
      let entries: [StableBlockEntry] = runs.indices.map { index in
        let run = runs[index]
        let text = String(content[run.range].characters)
        let hash = text.hashValue
        let occurrence = hashCounts[hash, default: 0]
        hashCounts[hash] = occurrence + 1
        return StableBlockEntry(id: "\(hash).\(occurrence)", index: index)
      }

      BlockVStack {
        ForEach(entries) { entry in
          let run = runs[entry.index]
          Block(intent: run.intent, content: content[run.range])
        }
      }
    }
  }

  /// Lightweight wrapper giving each block run a stable, content-based identity.
  fileprivate struct StableBlockEntry: Identifiable {
    let id: String
    let index: Int
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
