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
            HStack(spacing: 4) {
                if let icon = NanIcon.menuBar {
                    Image(nsImage: icon)
                        .renderingMode(.original)
                }
                if model.menuBarStyle == .iconAndTotal {
                    Text(model.menuTitle)
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
