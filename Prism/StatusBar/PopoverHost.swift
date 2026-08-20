import AppKit
import SwiftUI

@MainActor
final class PopoverHost {
    let popover: NSPopover

    init(environment: AppEnvironment) {
        popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentSize = NSSize(width: 360, height: 300)
        let controller = NSHostingController(
            rootView: MenuBarPopoverView()
                .environment(environment)
        )
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
    }
}
