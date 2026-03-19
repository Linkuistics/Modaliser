import AppKit

/// Loads and caches app icons for chooser choices.
/// Supports two icon types: "bundleId" (resolved via NSWorkspace) and "path" (direct file icon).
final class IconLoader {
    static let shared = IconLoader()
    private var cache: [String: NSImage] = [:]

    func icon(for choice: ChooserChoice) -> NSImage? {
        guard let iconValue = choice.icon, !iconValue.isEmpty else { return nil }
        let cacheKey = "\(choice.iconType ?? "path"):\(iconValue)"
        if let cached = cache[cacheKey] { return cached }

        let image: NSImage?
        switch choice.iconType {
        case "bundleId":
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: iconValue) {
                image = NSWorkspace.shared.icon(forFile: url.path)
            } else {
                image = nil
            }
        default:
            image = NSWorkspace.shared.icon(forFile: iconValue)
        }

        if let image {
            image.size = NSSize(width: 32, height: 32)
            cache[cacheKey] = image
        }
        return image
    }

    func clearCache() {
        cache.removeAll()
    }
}
