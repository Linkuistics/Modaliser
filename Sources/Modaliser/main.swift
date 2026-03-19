import AppKit

// MARK: - Application entry point

let app = NSApplication.shared
let delegate = ModaliserAppDelegate()
app.delegate = delegate
app.run()
