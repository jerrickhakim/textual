import Foundation

/// A ``MarkupParser`` that pre-processes handlebars (`{{component}}`) in the input,
/// replaces them with sentinel characters, parses the remaining markdown via Foundation,
/// then injects ``ChatComponentData`` attributes at the sentinel positions.
public struct ChatMarkupParser: MarkupParser {
    private let baseURL: URL?
    private let options: AttributedString.MarkdownParsingOptions

    public init(baseURL: URL? = nil) {
        self.baseURL = baseURL
        self.options = .init()
    }

    public func attributedString(for input: String) throws -> AttributedString {
        // 1. Extract handlebars components and replace with sentinels
        let extraction = extractComponents(from: input)

        // 2. Parse the cleaned markdown via Foundation
        var result = try AttributedString(
            markdown: extraction.cleanedMarkdown,
            including: \.textual,
            options: options,
            baseURL: baseURL
        )

        // 3. Find sentinels in the result and inject ChatComponentData attributes
        let characters = String(result.characters)
        var searchStart = characters.startIndex
        for (index, component) in extraction.components.enumerated() {
            let sentinel = Self.sentinel(for: index)
            guard let range = characters.range(of: sentinel, range: searchStart..<characters.endIndex) else {
                continue
            }
            injectComponent(component, range: range, in: characters, into: &result)
            searchStart = range.upperBound
        }

        return result
    }

    // MARK: - Sentinel Generation

    static func sentinel(for index: Int) -> String {
        "\u{FFFC}\u{200B}\(index)\u{200B}"
    }

    // MARK: - Component Extraction

    struct ExtractionResult {
        let cleanedMarkdown: String
        let components: [ChatComponentData]
    }

    /// Scans input for handlebars blocks, extracts component data, and replaces with sentinels.
    /// Tracks code fence state to avoid parsing handlebars inside ``` blocks.
    func extractComponents(from input: String) -> ExtractionResult {
        var components: [ChatComponentData] = []
        var result = ""
        var i = input.startIndex
        var insideCodeFence = false
        var atLineStart = true

        while i < input.endIndex {
            // Track code fences at line start
            if atLineStart {
                let remaining = input[i...]
                let trimmed = remaining.prefix(while: { $0 == " " || $0 == "\t" })
                let afterTrim = input.index(i, offsetBy: trimmed.count, limitedBy: input.endIndex) ?? input.endIndex
                if input[afterTrim...].hasPrefix("```") {
                    insideCodeFence.toggle()
                }
            }

            atLineStart = (input[i] == "\n")

            // Inside code fence — pass through verbatim
            if insideCodeFence {
                result.append(input[i])
                i = input.index(after: i)
                continue
            }

            // Look for {{ opening
            guard input[i...].hasPrefix("{{") else {
                result.append(input[i])
                i = input.index(after: i)
                continue
            }

            let openStart = i
            let afterOpen = input.index(i, offsetBy: 2)

            // Check for closing tag {{/name}} — skip (already consumed by block parse)
            if afterOpen < input.endIndex && input[afterOpen] == "/" {
                if let closeEnd = input[afterOpen...].range(of: "}}") {
                    i = closeEnd.upperBound
                    continue
                }
            }

            // Find closing }}
            guard let closeRange = input[afterOpen...].range(of: "}}") else {
                result.append(contentsOf: "{{")
                i = afterOpen
                continue
            }

            let tagContent = String(input[afterOpen..<closeRange.lowerBound])
            let parsed = parseTagContent(tagContent)

            guard let componentType = ChatComponentType(rawValue: parsed.name) else {
                // Unknown component — pass through verbatim
                let fullTag = String(input[openStart..<closeRange.upperBound])
                result.append(contentsOf: fullTag)
                i = closeRange.upperBound
                continue
            }

            let afterTag = closeRange.upperBound

            // Look for closing tag {{/name}} to determine block vs self-closing
            let closingTag = "{{/\(parsed.name)}}"
            if let closingRange = input[afterTag...].range(of: closingTag) {
                // Block component with content
                var blockContent = String(input[afterTag..<closingRange.lowerBound])
                // Trim leading/trailing newlines
                if blockContent.hasPrefix("\n") { blockContent = String(blockContent.dropFirst()) }
                if blockContent.hasSuffix("\n") { blockContent = String(blockContent.dropLast()) }

                let component = ChatComponentData(
                    type: componentType,
                    attributes: parsed.attributes,
                    content: blockContent
                )
                let sentinelStr = Self.sentinel(for: components.count)
                components.append(component)
                result.append(contentsOf: sentinelStr)
                result.append("\n\n")
                i = closingRange.upperBound
            } else {
                // Self-closing component
                let component = ChatComponentData(
                    type: componentType,
                    attributes: parsed.attributes
                )
                let sentinelStr = Self.sentinel(for: components.count)
                components.append(component)
                result.append(contentsOf: sentinelStr)
                result.append("\n\n")
                i = afterTag
            }
        }

        return ExtractionResult(cleanedMarkdown: result, components: components)
    }

    // MARK: - Tag Content Parsing

    struct ParsedTag {
        let name: String
        let attributes: [String: String]
    }

    func parseTagContent(_ content: String) -> ParsedTag {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        var scanner = trimmed[...]

        // Extract component name (first word)
        let nameEnd = scanner.firstIndex(where: { $0.isWhitespace }) ?? scanner.endIndex
        let name = String(scanner[..<nameEnd])

        if nameEnd >= scanner.endIndex {
            return ParsedTag(name: name, attributes: [:])
        }
        scanner = scanner[scanner.index(after: nameEnd)...]

        // Parse key="value" pairs
        var attrs: [String: String] = [:]
        while !scanner.isEmpty {
            scanner = scanner.drop(while: { $0.isWhitespace })
            guard !scanner.isEmpty else { break }

            guard let eqIndex = scanner.firstIndex(of: "=") else { break }
            let key = String(scanner[..<eqIndex]).trimmingCharacters(in: .whitespaces)
            scanner = scanner[scanner.index(after: eqIndex)...]

            scanner = scanner.drop(while: { $0.isWhitespace })
            guard scanner.first == "\"" else { break }
            scanner = scanner[scanner.index(after: scanner.startIndex)...]

            guard let closeQuote = scanner.firstIndex(of: "\"") else { break }
            attrs[key] = String(scanner[..<closeQuote])
            scanner = scanner[scanner.index(after: closeQuote)...]
        }

        return ParsedTag(name: name, attributes: attrs)
    }

    // MARK: - Component Injection

    private func injectComponent(
        _ component: ChatComponentData,
        range: Range<String.Index>,
        in characters: String,
        into attributedString: inout AttributedString
    ) {
        let startOffset = characters.distance(from: characters.startIndex, to: range.lowerBound)
        let endOffset = characters.distance(from: characters.startIndex, to: range.upperBound)

        let attrStart = attributedString.index(
            attributedString.startIndex,
            offsetByCharacters: startOffset
        )
        let attrEnd = attributedString.index(
            attributedString.startIndex,
            offsetByCharacters: endOffset
        )

        attributedString[attrStart..<attrEnd][ChatComponentKey.self] = component
    }
}
