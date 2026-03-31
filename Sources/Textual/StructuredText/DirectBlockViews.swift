import SwiftUI

// MARK: - Direct Block Views
//
// Public views that render individual block types directly, bypassing full-document
// markdown parsing and block-run splitting. Each view accepts raw content (String)
// and renders it through the same style pipeline as StructuredText, but skips:
//
// 1. Foundation's `AttributedString(markdown:)` full-document parse
// 2. BlockContent's block-run splitting and StableBlockRun hashing
// 3. FrozenBlock's equatable comparison
//
// For blocks containing inline formatting (paragraphs, headings, list items, etc.),
// an inline-only parse is used instead of the full markdown parser.
// For code blocks, no markdown parsing is performed at all.

// MARK: - Inline Content Helper

/// Shared helper that parses inline-only markdown and renders through the standard
/// TextFragment pipeline with inline style support, attachments, and text selection.
private struct InlineContent: View {
  @State private var attributedString = AttributedString()
  @State private var suffixOpacity: Double = 1

  private let inlineMarkdown: String
  private let isStreaming: Bool
  private let syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension]

  /// Cache for inline-only parsed attributed strings.
  private static let parseCache: NSCache<NSString, ParseCacheEntry> = {
    let cache = NSCache<NSString, ParseCacheEntry>()
    cache.countLimit = 256
    return cache
  }()

  private final class ParseCacheEntry {
    let attributedString: AttributedString
    init(_ attributedString: AttributedString) {
      self.attributedString = attributedString
    }
  }

  init(
    _ inlineMarkdown: String,
    isStreaming: Bool = false,
    syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] = []
  ) {
    self.inlineMarkdown = inlineMarkdown
    self.isStreaming = isStreaming
    self.syntaxExtensions = syntaxExtensions
  }

  var body: some View {
    Group {
      if isStreaming {
        streamingText
      } else {
        normalText
      }
    }
    .onChange(of: inlineMarkdown, initial: true) { old, new in
      parseInline(new)
      if isStreaming && !old.isEmpty && new.count > old.count {
        suffixOpacity = 0
         withAnimation(.easeIn(duration: 0.4)) { 
          suffixOpacity = 1
        }
      }
    }
    .lineLimit(nil)
  }

  /// Streaming path: uses Text concatenation to fade in the last word.
  /// Sets foreground color alpha on the suffix AttributedString so both sides
  /// remain `Text` and the `+` operator works for inline paragraph flow.
  @ViewBuilder
  private var streamingText: some View {
    if let splitIdx = lastWordSplitIndex {
      let prefix = AttributedString(attributedString[attributedString.startIndex..<splitIdx])
      let suffix = {
        var s = AttributedString(attributedString[splitIdx..<attributedString.endIndex])
        s.foregroundColor = Color.primary.opacity(suffixOpacity)
        return s
      }()
      (Text(prefix) + Text(suffix))
    } else {
      Text(attributedString)
    }
  }

  /// Normal path: full TextFragment pipeline with attachments, inline styles, selection.
  private var normalText: some View {
    WithAttachments(attributedString) {
      WithInlineStyle($0) {
        TextFragment($0)
          .modifier(TextSelectionInteraction())
      }
    }
    .coordinateSpace(.textContainer)
  }

  /// Finds the start index of the last word in the attributed string.
  private var lastWordSplitIndex: AttributedString.Index? {
    let chars = attributedString.characters
    guard chars.count > 1 else { return nil }
    var idx = chars.index(before: chars.endIndex)
    while idx > chars.startIndex {
      if chars[idx].isWhitespace {
        let next = chars.index(after: idx)
        return next < chars.endIndex ? next : nil
      }
      idx = chars.index(before: idx)
    }
    return nil
  }

  private func parseInline(_ markup: String) {
    let key = markup as NSString
    if let cached = Self.parseCache.object(forKey: key) {
      self.attributedString = cached.attributedString
      return
    }
    let parser = AttributedStringMarkdownParser.inlineMarkdown(syntaxExtensions: syntaxExtensions)
    let result = (try? parser.attributedString(for: markup)) ?? AttributedString()
    Self.parseCache.setObject(ParseCacheEntry(result), forKey: key)
    self.attributedString = result
  }
}

// MARK: - Direct Paragraph

extension StructuredText {
  /// Renders inline markdown as a styled paragraph, bypassing full-document parsing.
  public struct DirectParagraph: View {
    @Environment(\.paragraphStyle) private var paragraphStyle

    private let inlineMarkdown: String
    private let isStreaming: Bool
    private let syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension]

    public init(
      inlineMarkdown: String,
      isStreaming: Bool = false,
      syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] = []
    ) {
      self.inlineMarkdown = inlineMarkdown
      self.isStreaming = isStreaming
      self.syntaxExtensions = syntaxExtensions
    }

    public var body: some View {
      let configuration = BlockStyleConfiguration(
        label: .init(InlineContent(inlineMarkdown, isStreaming: isStreaming, syntaxExtensions: syntaxExtensions)),
        indentationLevel: 0
      )
      AnyView(paragraphStyle.resolve(configuration: configuration))
    }
  }
}

// MARK: - Direct Heading

extension StructuredText {
  /// Renders inline markdown as a styled heading, bypassing full-document parsing.
  public struct DirectHeading: View {
    @Environment(\.headingStyle) private var headingStyle

    private let inlineMarkdown: String
    private let level: Int
    private let syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension]

    public init(
      inlineMarkdown: String,
      level: Int,
      syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] = []
    ) {
      self.inlineMarkdown = inlineMarkdown
      self.level = level
      self.syntaxExtensions = syntaxExtensions
    }

    public var body: some View {
      let configuration = HeadingStyleConfiguration(
        label: .init(InlineContent(inlineMarkdown, syntaxExtensions: syntaxExtensions)),
        indentationLevel: 0,
        headingLevel: level
      )
      AnyView(headingStyle.resolve(configuration: configuration))
    }
  }
}

// MARK: - Direct Code Block

extension StructuredText {
  /// Renders raw code with syntax highlighting, bypassing ALL markdown parsing.
  public struct DirectCodeBlock: View {
    @Environment(\.highlighterTheme) private var highlighterTheme
    @Environment(\.codeBlockStyle) private var codeBlockStyle

    private let code: String
    private let languageHint: String?

    public init(code: String, languageHint: String? = nil) {
      // Strip trailing newline to match internal CodeBlock behavior
      if code.hasSuffix("\n") {
        self.code = String(code.dropLast())
      } else {
        self.code = code
      }
      self.languageHint = languageHint
    }

    public var body: some View {
      let attributed = AttributedString(code)
      let substring = attributed[attributed.startIndex..<attributed.endIndex]

      let configuration = CodeBlockStyleConfiguration(
        label: .init(
          HighlightedTextFragment(
            substring,
            languageHint: languageHint,
            theme: highlighterTheme
          )
          .modifier(TextSelectionInteraction())
          .coordinateSpace(.textContainer)
        ),
        indentationLevel: 0,
        languageHint: languageHint,
        codeBlock: .init(code: code),
        highlighterTheme: highlighterTheme
      )
      AnyView(codeBlockStyle.resolve(configuration: configuration))
    }
  }
}

// MARK: - Direct Block Quote

extension StructuredText {
  /// Renders inline markdown as a block quote, bypassing full-document parsing.
  public struct DirectBlockQuote: View {
    @Environment(\.blockQuoteStyle) private var blockQuoteStyle

    private let inlineMarkdown: String
    private let syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension]

    public init(
      inlineMarkdown: String,
      syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] = []
    ) {
      self.inlineMarkdown = inlineMarkdown
      self.syntaxExtensions = syntaxExtensions
    }

    public var body: some View {
      let configuration = BlockStyleConfiguration(
        label: .init(InlineContent(inlineMarkdown, syntaxExtensions: syntaxExtensions)),
        indentationLevel: 0
      )
      AnyView(blockQuoteStyle.resolve(configuration: configuration))
    }
  }
}

// MARK: - Direct Thematic Break

extension StructuredText {
  /// Renders a thematic break (horizontal rule). No parsing needed.
  public struct DirectThematicBreak: View {
    @Environment(\.thematicBreakStyle) private var thematicBreakStyle

    public init() {}

    public var body: some View {
      let configuration = BlockStyleConfiguration(
        label: .init(EmptyView()),
        indentationLevel: 0
      )
      AnyView(thematicBreakStyle.resolve(configuration: configuration))
    }
  }
}

// MARK: - Direct Unordered List Item

extension StructuredText {
  /// Renders an unordered list item with inline markdown text, bypassing full-document parsing.
  public struct DirectUnorderedListItem: View {
    @Environment(\.listItemStyle) private var listItemStyle
    @Environment(\.unorderedListMarker) private var unorderedListMarker

    private let inlineMarkdown: String
    private let depth: Int
    private let syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension]

    public init(
      inlineMarkdown: String,
      depth: Int = 0,
      syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] = []
    ) {
      self.inlineMarkdown = inlineMarkdown
      self.depth = depth
      self.syntaxExtensions = syntaxExtensions
    }

    public var body: some View {
      // Textual uses 1-based indentation levels (from PresentationIntent),
      // but the app passes 0-based depth. Convert here.
      let level = depth + 1
      let marker = AnyView(
        unorderedListMarker.resolve(
          configuration: .init(indentationLevel: level)
        )
      )
      let configuration = ListItemStyleConfiguration(
        marker: .init(marker),
        block: .init(InlineContent(inlineMarkdown, syntaxExtensions: syntaxExtensions)),
        indentationLevel: level
      )
      AnyView(listItemStyle.resolve(configuration: configuration))
    }
  }
}

// MARK: - Direct Ordered List Item

extension StructuredText {
  /// Renders an ordered list item with inline markdown text, bypassing full-document parsing.
  public struct DirectOrderedListItem: View {
    @Environment(\.listItemStyle) private var listItemStyle
    @Environment(\.orderedListMarker) private var orderedListMarker

    private let inlineMarkdown: String
    private let depth: Int
    private let ordinal: Int
    private let syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension]

    public init(
      inlineMarkdown: String,
      depth: Int = 0,
      ordinal: Int = 1,
      syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] = []
    ) {
      self.inlineMarkdown = inlineMarkdown
      self.depth = depth
      self.ordinal = ordinal
      self.syntaxExtensions = syntaxExtensions
    }

    public var body: some View {
      let level = depth + 1
      let marker = AnyView(
        orderedListMarker.resolve(
          configuration: .init(
            indentationLevel: level,
            ordinal: ordinal
          )
        )
      )
      let configuration = ListItemStyleConfiguration(
        marker: .init(marker),
        block: .init(InlineContent(inlineMarkdown, syntaxExtensions: syntaxExtensions)),
        indentationLevel: level
      )
      AnyView(listItemStyle.resolve(configuration: configuration))
    }
  }
}

// MARK: - Direct Table

extension StructuredText {
  /// Renders a table from pre-parsed header and row data, bypassing markdown table parsing.
  public struct DirectTable: View {
    @Environment(\.tableStyle) private var tableStyle

    @State private var spacing = TableCell.Spacing()

    private let header: [String]
    private let rows: [[String]]
    private let syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension]

    public init(
      header: [String],
      rows: [[String]],
      syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] = []
    ) {
      self.header = header
      self.rows = rows
      self.syntaxExtensions = syntaxExtensions
    }

    public var body: some View {
      let configuration = TableStyleConfiguration(
        label: .init(label),
        indentationLevel: 0
      )
      let resolvedStyle = tableStyle.resolve(configuration: configuration)
        .onPreferenceChange(TableCell.SpacingKey.self) { @MainActor in
          spacing = $0
        }

      AnyView(resolvedStyle)
    }

    @ViewBuilder
    private var label: some View {
      Grid(horizontalSpacing: spacing.horizontal, verticalSpacing: spacing.vertical) {
        // Header row
        GridRow {
          ForEach(header.indices, id: \.self) { columnIndex in
            DirectTableCell(
              text: header[columnIndex],
              row: 0,
              column: columnIndex,
              syntaxExtensions: syntaxExtensions
            )
          }
        }
        // Data rows
        ForEach(rows.indices, id: \.self) { rowIndex in
          GridRow {
            ForEach(rows[rowIndex].indices, id: \.self) { columnIndex in
              DirectTableCell(
                text: rows[rowIndex][columnIndex],
                row: rowIndex + 1,  // +1 because header is row 0
                column: columnIndex,
                syntaxExtensions: syntaxExtensions
              )
            }
          }
        }
      }
    }
  }

  /// A table cell that parses inline markdown for its content.
  struct DirectTableCell: View {
    @Environment(\.tableCellStyle) private var tableCellStyle

    private let text: String
    private let row: Int
    private let column: Int
    private let syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension]

    init(
      text: String,
      row: Int,
      column: Int,
      syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] = []
    ) {
      self.text = text
      self.row = row
      self.column = column
      self.syntaxExtensions = syntaxExtensions
    }

    var body: some View {
      let identifier = TableCell.Identifier(row: row, column: column)
      let configuration = TableCellStyleConfiguration(
        label: .init(InlineContent(text, syntaxExtensions: syntaxExtensions)),
        indentationLevel: 0,
        row: row,
        column: column
      )
      let resolvedStyle = tableCellStyle
        .resolve(configuration: configuration)
        .anchorPreference(key: TableCell.BoundsKey.self, value: .bounds) { anchor in
          [identifier: anchor]
        }

      AnyView(resolvedStyle)
    }
  }
}
