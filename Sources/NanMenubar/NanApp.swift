import SwiftUI

@main
struct NanApp: App {
    @StateObject private var model: AppModel

    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        model.start()
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardView()
                .environmentObject(model)
        } label: {
            if let image = MenuBarLabel.image(for: model) {
                Image(nsImage: image)
                    .renderingMode(.original)
            } else {
                Text("NaN")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
