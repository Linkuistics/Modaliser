import Foundation
import LispKit

/// Native LispKit library providing quicklinks from a user-edited .scm file.
/// Scheme name: (modaliser quicklinks)
///
/// Swift provides the config directory path.
/// Scheme handles file reading, parsing, transformation, and filtering.
///
/// Provides: get-quicklinks
final class QuicklinksLibrary: NativeLibrary {
    var configDirectory: String = NSHomeDirectory() + "/.config/modaliser"

    public required init(in context: Context) throws {
        try super.init(in: context)
    }

    public override class var name: [String] {
        ["modaliser", "quicklinks"]
    }

    public override func dependencies() {
        self.`import`(from: ["lispkit", "base"])
    }

    public override func declarations() {
        self.define(Procedure("quicklinks-config-path", configPathFunction))

        self.define("quicklinks--rename-name-to-text", via:
            "(define (quicklinks--rename-name-to-text entry) ",
            "  (map (lambda (field) ",
            "         (if (and (pair? field) (eq? (car field) 'name)) ",
            "           (cons 'text (cdr field)) ",
            "           field)) ",
            "       entry))"
        )

        self.define("quicklinks--extract-tag", via:
            "(define (quicklinks--extract-tag rest) ",
            "  (cond ",
            "    ((null? rest) #f) ",
            "    ((and (pair? rest) (eq? (car rest) 'tag) (pair? (cdr rest))) ",
            "     (car (cdr rest))) ",
            "    (else #f)))"
        )

        self.define("quicklinks--has-tag?", via:
            "(define (quicklinks--has-tag? entry tag) ",
            "  (let ((tags-field (assoc 'tags entry))) ",
            "    (if tags-field ",
            "      (member tag (cdr tags-field)) ",
            "      #f)))"
        )

        self.define("get-quicklinks", via:
            "(define (get-quicklinks . rest) ",
            "  (let ((path (string-append (quicklinks-config-path) \"/quicklinks.scm\"))) ",
            "    (if (file-exists? path) ",
            "      (let ((entries (call-with-input-file path read))) ",
            "        (let ((transformed (map quicklinks--rename-name-to-text entries))) ",
            "          (let ((tag (quicklinks--extract-tag rest))) ",
            "            (if tag ",
            "              (filter (lambda (e) (quicklinks--has-tag? e tag)) transformed) ",
            "              transformed)))) ",
            "      '())))"
        )
    }

    // MARK: - Native functions

    /// (quicklinks-config-path) -> string
    private func configPathFunction() -> Expr {
        .makeString(configDirectory)
    }
}
