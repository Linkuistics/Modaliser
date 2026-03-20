import Foundation
import LispKit

/// Native LispKit library providing snippets from a user-edited .scm file.
/// Scheme name: (modaliser snippets)
///
/// Swift provides config path and template expansion (date/time formatting).
/// Scheme handles file reading, parsing, transformation, and filtering.
///
/// Provides: get-snippets, expand-snippet
final class SnippetsLibrary: NativeLibrary {
    var configDirectory: String = NSHomeDirectory() + "/.config/modaliser"

    public required init(in context: Context) throws {
        try super.init(in: context)
    }

    public override class var name: [String] {
        ["modaliser", "snippets"]
    }

    public override func dependencies() {
        self.`import`(from: ["lispkit", "base"])
        self.`import`(from: ["modaliser", "pasteboard"], "get-clipboard")
    }

    public override func declarations() {
        self.define(Procedure("snippets-config-path", configPathFunction))
        self.define(Procedure("snippets--current-date", currentDateFunction))
        self.define(Procedure("snippets--current-time", currentTimeFunction))
        self.define(Procedure("snippets--current-datetime", currentDatetimeFunction))
        self.define(Procedure("snippets--string-replace", stringReplaceFunction))

        // Reuse the same file-reading and tag-filtering pattern as QuicklinksLibrary.
        self.define("snippets--rename-name-to-text", via:
            "(define (snippets--rename-name-to-text entry) ",
            "  (map (lambda (field) ",
            "         (if (and (pair? field) (eq? (car field) 'name)) ",
            "           (cons 'text (cdr field)) ",
            "           field)) ",
            "       entry))"
        )

        self.define("snippets--extract-tag", via:
            "(define (snippets--extract-tag rest) ",
            "  (cond ",
            "    ((null? rest) #f) ",
            "    ((and (pair? rest) (eq? (car rest) 'tag) (pair? (cdr rest))) ",
            "     (car (cdr rest))) ",
            "    (else #f)))"
        )

        self.define("snippets--has-tag?", via:
            "(define (snippets--has-tag? entry tag) ",
            "  (let ((tags-field (assoc 'tags entry))) ",
            "    (if tags-field ",
            "      (member tag (cdr tags-field)) ",
            "      #f)))"
        )

        self.define("get-snippets", via:
            "(define (get-snippets . rest) ",
            "  (let ((path (string-append (snippets-config-path) \"/snippets.scm\"))) ",
            "    (if (file-exists? path) ",
            "      (let ((entries (call-with-input-file path read))) ",
            "        (let ((transformed (map snippets--rename-name-to-text entries))) ",
            "          (let ((tag (snippets--extract-tag rest))) ",
            "            (if tag ",
            "              (filter (lambda (e) (snippets--has-tag? e tag)) transformed) ",
            "              transformed)))) ",
            "      '())))"
        )

        self.define("expand-snippet", via:
            "(define (expand-snippet template) ",
            "  (let* ((s1 (snippets--string-replace template \"{{date}}\" (snippets--current-date))) ",
            "         (s2 (snippets--string-replace s1 \"{{time}}\" (snippets--current-time))) ",
            "         (s3 (snippets--string-replace s2 \"{{datetime}}\" (snippets--current-datetime)))) ",
            "    (snippets--string-replace s3 \"{{clipboard}}\" (get-clipboard))))"
        )
    }

    // MARK: - Native functions

    private func configPathFunction() -> Expr {
        .makeString(configDirectory)
    }

    private func currentDateFunction() -> Expr {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return .makeString(formatter.string(from: Date()))
    }

    private func currentTimeFunction() -> Expr {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return .makeString(formatter.string(from: Date()))
    }

    private func currentDatetimeFunction() -> Expr {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return .makeString(formatter.string(from: Date()))
    }

    /// (snippets--string-replace str target replacement) -> string
    private func stringReplaceFunction(_ str: Expr, _ target: Expr, _ replacement: Expr) throws -> Expr {
        let s = try str.asString()
        let t = try target.asString()
        let r = try replacement.asString()
        return .makeString(s.replacingOccurrences(of: t, with: r))
    }
}
