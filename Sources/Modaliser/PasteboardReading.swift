import AppKit

/// Protocol to abstract NSPasteboard for testing.
protocol PasteboardReading {
    var changeCount: Int { get }
    var types: [NSPasteboard.PasteboardType]? { get }
    func data(forType: NSPasteboard.PasteboardType) -> Data?
    func string(forType: NSPasteboard.PasteboardType) -> String?
}

extension NSPasteboard: PasteboardReading {}
