import SwiftUI

/// Reads the chat component renderer from the environment and dispatches rendering.
struct ChatComponentView: View {
    let data: ChatComponentData
    @Environment(\.chatComponentRenderer) private var renderer

    var body: some View {
        if let renderer {
            renderer.view(for: data)
        } else {
            // Fallback: render content as plain text if no renderer is set
            if !data.content.isEmpty {
                Text(data.content)
            }
        }
    }
}
