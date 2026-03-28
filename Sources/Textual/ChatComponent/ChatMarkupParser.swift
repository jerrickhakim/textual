import Foundation

/// A ``MarkupParser`` that pre-processes handlebars (`{{component}}`) in the input,
/// replaces them with sentinel characters, parses the remaining markdown via Foundation,
/// then injects ``ChatComponentData`` attributes at the sentinel positions.
public struct ChatMarkupParser: MarkupParser {
    private let baseURL: URL?
    private let options: AttributedString.MarkdownParsingOptions

    private final class AttributedStringCacheEntry: NSObject {
        let value: AttributedString

        init(_ value: AttributedString) {
            self.value = value
        }
    }

    private enum SegmentCache {
        static let markdown = NSCache<NSString, AttributedStringCacheEntry>()
        static let component = NSCache<NSString, AttributedStringCacheEntry>()
    }

    public init(baseURL: URL? = nil) {
        self.baseURL = baseURL
        self.options = .init()
    }

    public func attributedString(for input: String) throws -> AttributedString {
        let segments = extractSegments(from: input)
        var result = AttributedString()

        for segment in segments {
            switch segment {
            case .markdown(let markdown):
                guard !markdown.isEmpty else { continue }
                result += try parsedMarkdownSegment(markdown)
            case .component(let component):
                result += try parsedComponentSegment(component)
            }
        }

        return result
    }

    // MARK: - Sentinel Generation

    static func sentinel(for index: Int) -> String {
        "\u{FFFC}\u{200B}\(index)\u{200B}"
    }

    // MARK: - Component Extraction

    private enum ExtractionSegment {
        case markdown(String)
        case component(ChatComponentData)
    }

    /// Scans input for handlebars blocks and emits interleaved markdown/component segments.
    /// Tracks code fence state to avoid parsing handlebars inside ``` blocks.
    func extractSegments(from input: String) -> [ExtractionSegment] {
        var segments: [ExtractionSegment] = []
        var markdownBuffer = ""
        var i = input.startIndex
        var insideCodeFence = false
        var atLineStart = true

        func flushMarkdownBuffer() {
            guard !markdownBuffer.isEmpty else { return }
            segments.append(.markdown(markdownBuffer))
            markdownBuffer.removeAll(keepingCapacity: true)
        }

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
                markdownBuffer.append(input[i])
                i = input.index(after: i)
                continue
            }

            // Look for {{ opening
            guard input[i...].hasPrefix("{{") else {
                markdownBuffer.append(input[i])
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
                markdownBuffer.append(contentsOf: "{{")
                i = afterOpen
                continue
            }

            let tagContent = String(input[afterOpen..<closeRange.lowerBound])
            let parsed = parseTagContent(tagContent)

            guard let componentType = ChatComponentType(rawValue: parsed.name) else {
                // Unknown component — pass through verbatim
                let fullTag = String(input[openStart..<closeRange.upperBound])
                markdownBuffer.append(contentsOf: fullTag)
                i = closeRange.upperBound
                continue
            }

            let afterTag = closeRange.upperBound
            flushMarkdownBuffer()

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
                segments.append(.component(component))
                i = closingRange.upperBound
            } else {
                // Self-closing component
                let component = ChatComponentData(
                    type: componentType,
                    attributes: parsed.attributes
                )
                segments.append(.component(component))
                i = afterTag
            }

            // Components render as standalone blocks, so swallow immediately
            // following blank lines to avoid duplicating spacing work.
            while i < input.endIndex && (input[i] == "\n" || input[i] == "\r") {
                i = input.index(after: i)
            }
        }

        flushMarkdownBuffer()
        return segments
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

    private func parsedMarkdownSegment(_ markdown: String) throws -> AttributedString {
        let key = cacheKey(prefix: "md", payload: markdown)
        if let cached = SegmentCache.markdown.object(forKey: key as NSString) {
            return cached.value
        }

        let parsed = try AttributedString(
            markdown: markdown,
            including: \.textual,
            options: options,
            baseURL: baseURL
        )
        SegmentCache.markdown.setObject(
            AttributedStringCacheEntry(parsed),
            forKey: key as NSString,
            cost: markdown.utf8.count
        )
        return parsed
    }

    private func parsedComponentSegment(_ component: ChatComponentData) throws -> AttributedString {
        let key = cacheKey(prefix: "component", payload: componentCachePayload(component))
        if let cached = SegmentCache.component.object(forKey: key as NSString) {
            return cached.value
        }

        let sentinel = Self.sentinel(for: 0)
        var parsed = try AttributedString(
            markdown: sentinel + "\n\n",
            including: \.textual,
            options: options,
            baseURL: baseURL
        )
        let characters = String(parsed.characters)
        if let range = characters.range(of: sentinel) {
            injectComponent(component, range: range, in: characters, into: &parsed)
        }

        SegmentCache.component.setObject(
            AttributedStringCacheEntry(parsed),
            forKey: key as NSString
        )
        return parsed
    }

    private func cacheKey(prefix: String, payload: String) -> String {
        let baseURLKey = baseURL?.absoluteString ?? ""
        return "\(prefix)|\(baseURLKey)|\(payload)"
    }

    private func componentCachePayload(_ component: ChatComponentData) -> String {
        let attrs = component.attributes
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        return "\(component.type.rawValue)|\(attrs)|\(component.content)"
    }

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
