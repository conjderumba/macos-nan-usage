import AppKit
import SwiftUI

enum NanIcon {
    /// The NaN brand mark, loaded from the app bundle resources.
    static var menuBar: NSImage? {
        guard let url = Bundle.main.url(forResource: "menubar-icon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = false
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}
