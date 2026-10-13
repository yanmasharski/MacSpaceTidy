import AppKit
import SwiftUI

struct MacSpaceTidyApp: App {
    private static let MIN_WIDTH: CGFloat = 760
    private static let MIN_HEIGHT: CGFloat = 600

    @State private var model = AppModel()

    init() {
        // Needed when started with `swift run` (no .app bundle).
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("MacSpaceTidy", id: "main") {
            ContentView(model: model)
                .frame(minWidth: MacSpaceTidyApp.MIN_WIDTH, minHeight: MacSpaceTidyApp.MIN_HEIGHT)
                .onAppear { NSApplication.shared.activate() }
        }
        Settings {
            SettingsView(model: model)
        }
    }
}
