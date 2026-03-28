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

      let useLazy = useLazyLayout || chatRenderer != nil

      if useLazy {
        LazyVStack(alignment: .leading, spacing: 12) {
          ForEach(entries) { entry in
            let run = runs[entry.index]
            let substring = content[run.range]

            if let component = substring.runs.first(where: { $0[ChatComponentKey.self] != nil })?[ChatComponentKey.self] {
              ChatComponentView(data: component)
            } else {
              Block(intent: run.intent, content: substring)
            }
          }
        }
      } else {
        BlockVStack {
          ForEach(entries) { entry in
            let run = runs[entry.index]
            Block(intent: run.intent, content: content[run.range])
          }
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
