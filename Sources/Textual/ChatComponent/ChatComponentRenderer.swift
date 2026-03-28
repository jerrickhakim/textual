import SwiftUI

/// Protocol for rendering custom chat components.
/// The app implements this to map component data to native SwiftUI views.
@MainActor
public protocol ChatComponentRendering: Sendable {
    func view(for component: ChatComponentData) -> AnyView
}

/// Environment key for the chat component renderer.
private struct ChatComponentRendererKey: @unchecked Sendable, EnvironmentKey {
    nonisolated static let defaultValue: (any ChatComponentRendering)? = nil
}

extension EnvironmentValues {
    public var chatComponentRenderer: (any ChatComponentRendering)? {
        get { self[ChatComponentRendererKey.self] }
        set { self[ChatComponentRendererKey.self] = newValue }
    }
}

extension View {
    /// Sets the chat component renderer for this view hierarchy.
    public func chatComponentRenderer(_ renderer: some ChatComponentRendering) -> some View {
        environment(\.chatComponentRenderer, renderer)
    }
}
