import AppKit

/// Ensures the config directory and a default config.scm exist on first run.
enum ConfigSetup {

    static let configDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/modaliser")
    }()

    static let configFile: URL = {
        configDirectory.appendingPathComponent("config.scm")
    }()

    /// Create the config directory and write a default config.scm if none exists.
    /// Returns the path to the config file.
    @discardableResult
    static func ensureConfigExists() -> String {
        let fm = FileManager.default
        let dir = configDirectory.path
        let file = configFile.path

        if !fm.fileExists(atPath: dir) {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            NSLog("Created config directory: %@", dir)
        }

        if !fm.fileExists(atPath: file) {
            try? defaultConfig.write(toFile: file, atomically: true, encoding: .utf8)
            NSLog("Wrote default config to: %@", file)
        }

        return file
    }

    /// Reveal the config directory in Finder.
    static func revealInFinder() {
        let path = configDirectory.path
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            try? fm.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.selectFile(configFile.path, inFileViewerRootedAtPath: path)
    }

    private static let defaultConfig = """
    ;; Modaliser configuration
    ;; This file is evaluated at startup. Reload from the menu bar icon.
    ;; Full reference: https://github.com/anthropics/modaliser

    ;; Leader keys
    (set-leader! 'global F18)
    (set-leader! 'local F17)

    ;; Helpers
    (define (keystroke mods key-name)
      (lambda () (send-keystroke mods key-name)))

    (define (open-url-action url)
      (lambda () (open-url url)))

    ;; Global command tree
    (define-tree 'global

      ;; Quick-launch
      (key "s" "Safari"
        (lambda () (launch-app "Safari")))
      (key "i" "iTerm"
        (lambda () (launch-app "iTerm")))
      (key "z" "Zed"
        (lambda () (launch-app "Zed")))
      (key " " "Spotlight"
        (keystroke '(cmd) " "))

      ;; Find
      (group "f" "Find"
        (selector "a" "Find Apps"
          'prompt "Find app..."
          'source find-installed-apps
          'on-select activate-app
          'remember "apps"
          'id-field "bundleId"
          'actions
            (list
              (action "Open" 'key 'primary
                'run (lambda (c) (activate-app c)))
              (action "Show in Finder" 'key 'secondary
                'run (lambda (c) (reveal-in-finder c)))
              (action "Copy Path"
                'run (lambda (c) (set-clipboard! (cdr (assoc 'path c)))))
              (action "Copy Bundle ID"
                'run (lambda (c) (set-clipboard! (cdr (assoc 'bundleId c)))))))

        (selector "f" "Find File"
          'prompt "Find file..."
          'file-roots (list "~")
          'on-select (lambda (c)
            (run-shell (string-append "/usr/bin/open \\"" (cdr (assoc 'path c)) "\\"")))))

      ;; Windows
      (group "w" "Windows"
        (key "c" "Center"
          (lambda () (center-window)))
        (key "m" "Maximise"
          (lambda () (toggle-fullscreen)))
        (key "r" "Restore"
          (lambda () (restore-window)))
        (selector "s" "Switch Window"
          'prompt "Select window..."
          'source list-windows
          'on-select focus-window)))
    """
}
