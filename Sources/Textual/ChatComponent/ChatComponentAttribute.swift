import Foundation

/// Types of custom chat components embedded in markdown via handlebars syntax.
public enum ChatComponentType: String, Codable, Hashable, Sendable {
    case user
    case thinking
    case tool
    case system
    case actions
    case step
    case typing
    case file
    case anchor
    case fill
}

/// Data attached to an AttributedString run marking it as a custom chat component.
public struct ChatComponentData: Codable, Hashable, Sendable {
    public let type: ChatComponentType
    public let attributes: [String: String]
    public let content: String

    public init(type: ChatComponentType, attributes: [String: String], content: String = "") {
        self.type = type
        self.attributes = attributes
        self.content = content
    }
}

/// AttributedString key for chat component data.
public enum ChatComponentKey: CodableAttributedStringKey {
    public typealias Value = ChatComponentData
    public static let name = "textual.chatComponent"
}

extension AttributeScopes.TextualAttributes {
    public var chatComponent: ChatComponentKey.Type { ChatComponentKey.self }
}
