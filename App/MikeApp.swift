import SwiftUI

@main
struct MikeApp: App {
    @State private var model = MikeModel()

    var body: some Scene {
        Window("Mike", id: "main") {
            MikeMenu(model: model)
        }
        .defaultSize(width: 400, height: 300)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MikeMenu(model: model)
        } label: {
            Label("Mike", systemImage: model.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
