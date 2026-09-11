;; (modaliser tools grove) — live-leaf lookup and pure task-path recognition.
;;
;; grove drives a long workstream as a VCS-tracked tree of task files
;; under `.grove/` in a working tree, exactly one of which is the LIVE
;; LEAF: the task a session is on right now. Somebody working several
;; groves at once — one per worktree, one editor window per worktree —
;; opens that file by hand, per tree, all day. This library answers the
;; one question that automates away: given a worktree, WHICH FILE IS ITS
;; LIVE LEAF.
;;
;; Pure task-path recognition also selects stale resources without an existing
;; grove. For live-leaf lookup, grove's `grove-llm`
;; CLI has a dozen verbs; all but one of them WRITE — they create,
;; decompose, retire and prune tasks, and they are the province of the
;; agent running the session, not of a keyboard shortcut. `pick` is the
;; single read, so it is the single thing wrapped here.
;;
;; Quick start (prefix-style, as with every peer tools module):
;;
;;   (import (prefix (modaliser tools grove) grove:))
;;   (grove:live-leaf "/Users/me/Development/project")
;;     → "/Users/me/Development/project/.grove/03-impl--thing-k7.md"  or #f
;;
;; Nothing here knows about an editor, and nothing about an editor knows
;; about this: WHERE the returned path is then opened — an editor, a
;; terminal pane, a chooser — is the caller's business, and the caller is
;; user configuration. `Scheme/examples/vscode.scm` composes it with
;; `(modaliser apps vscode)` into "open this window's grove leaf and land
;; the explorer on it"; the two libraries never reference each other.
;;
;; ─── #f is an ORDINARY answer, not an error ─────────────────────────
;;
;; Three of the four outcomes are "no leaf", and none of them is a fault
;; worth raising into a leader press (ADR-0017 — a press must never
;; raise). Established by running the CLI, not from its documentation:
;;
;;   the directory is not a grove   `grove-llm pick` exits 1, prints
;;                                  "grove root not found: …/.grove" on
;;                                  STDERR, and nothing on stdout.
;;   the grove has no live leaves   exits 0, prints "grove <name>: no
;;                                  live leaves; this grove is done" on
;;                                  STDERR, nothing on stdout.
;;   the directory is not a VCS     exits 1, diagnostic on STDERR,
;;   working tree at all            nothing on stdout.
;;   a live leaf exists             exits 0, its ABSOLUTE path on
;;                                  STDOUT, one line.
;;
;; So every negative outcome is already "empty stdout", which is the
;; degradation the shell seam hands back when no runner is installed at
;; all (ADR-0023). One code path covers a missing binary, an absent
;; grove, a finished grove and a bare test engine: #f.
;;
;; ─── The session guard, and why the command unsets a variable ───────
;;
;; `grove-llm pick` refuses when the working tree it resolves is not the
;; one the CALLING SESSION belongs to, and it identifies that session by
;; the `GROVE_SIGNAL_FILE` variable in its environment. The refusal is a
;; SESSION guard, not a tree property: the same directory answers or
;; refuses depending on who is asking.
;;
;; A GUI-launched Modaliser has no such variable and would never trip
;; it. But one launched from a shell that has one — an agent's own
;; terminal, running the debug binary — inherits it, and then this
;; library reports "no leaf" for every worktree but that session's own,
;; which reads as a broken lookup rather than as a guard. Observed, not
;; imagined: it is how the guard was found.
;;
;; So the command clears the variable. That is not defeating the guard,
;; it is answering it truthfully — this invocation is not part of any
;; grove session, whatever the surrounding shell is part of — and it
;; makes the answer independent of how Modaliser was started. `pick` is
;; a read; every writing verb stays where it is, in the hands of the
;; session that owns the tree.

(define-library (modaliser tools grove)
  (export ;; ── The question ───────────────────────────────────────────
          ;; (live-leaf worktree) → the absolute path of that worktree's
          ;; live grove leaf, or #f when there isn't one. Impure: it runs
          ;; the CLI through the portable shell seam.
          live-leaf
          task-path?
          ;; The two pure halves it is built from — the command it would
          ;; spawn, and the reading of what came back. Exported because
          ;; that is where the behaviour is and therefore where the tests
          ;; land, the same split `(modaliser apps vscode)` keeps.
          live-leaf-command
          leaf-of-output)
  (import (scheme base)
          (only (modaliser util) string-trim string-split string-join filter)
          (only (srfi 1) every)
          ;; The canonical POSIX single-quote escaper. A worktree path is
          ;; arbitrary text arriving from an editor's stored state — it
          ;; may hold a space, and it may hold a quote — and it is
          ;; interpolated into a shell word below.
          (only (modaliser dialogs) sq-escape)
          (only (modaliser shell) run-shell)
          ;; Narrowly, for the PATH preamble. Every CLI-driven module in
          ;; the tree reaches into the terminal façade for this one
          ;; string; relocating it to a neutral home is a separate
          ;; concern (see `(modaliser wms paneru)`, which says the same).
          (only (modaliser terminal) tool-path-prefix))
  (begin

    ;; Grove 20's task filename grammar, including terminal outcomes.
    ;; This is lexical recognition, not a filesystem/existence check.
    (define task-kinds
      '("requirements" "design" "planning" "prototype" "impl"
        "review-requirements" "review-design" "review-planning"
        "review-prototype" "review-impl" "integrate-review-requirements"
        "integrate-review-design" "integrate-review-planning"
        "integrate-review-prototype" "integrate-review-impl"
        "research-a" "research-b" "combine-research" "finish"))

    (define (decimal? text)
      (and (not (string=? text ""))
           (every (lambda (c) (char<=? #\0 c #\9)) (string->list text))))

    (define (slug-word? text)
      (and (not (string=? text ""))
           (every (lambda (c) (or (char<=? #\a c #\z)
                                  (char<=? #\0 c #\9)))
                  (string->list text))))

    (define (task-filename? name)
      (let ((halves (string-split name "--")))
        (and (= (length halves) 2)
             (let* ((prefix (string-split (car halves) "-"))
                    (position (car prefix))
                    (rest (cdr prefix))
                    (kind (if (and (pair? rest)
                                   (member (car rest) '("DONE" "ABANDONED")))
                              (cdr rest) rest))
                    (suffix (string-split (cadr halves) ".")))
               (and (= (string-length position) 2) (decimal? position)
                    (member (string-join kind "-") task-kinds)
                    (= (length suffix) 2) (string=? (cadr suffix) "md")
                    (let* ((words (reverse (string-split (car suffix) "-")))
                           (key (string->list (car words))))
                      (and (pair? (cdr words)) (every slug-word? (cdr words))
                           (pair? key) (char=? (car key) #\k)
                           (decimal? (list->string (cdr key))) #t)))))))

    ;; Compare directory components, never a workspace-name prefix or an
    ;; arbitrary .grove substring. Reject traversal rather than resolving it
    ;; through a directory that may already have been deleted.
    (define (absolute-components path)
      (and (string? path) (not (string=? path ""))
           (char=? (car (string->list path)) #\/)
           (let ((parts (filter (lambda (s) (not (string=? s "")))
                                 (string-split path "/"))))
             (and (not (member "." parts)) (not (member ".." parts)) parts))))

    (define (task-path? path worktree)
      (let ((parts (absolute-components path))
            (root (absolute-components worktree)))
        (and parts root
             (let walk ((remaining parts) (prefix (append root '(".grove"))))
               (if (null? prefix)
                   (and (pair? remaining) (task-filename? (car (reverse remaining))))
                   (and (pair? remaining) (string=? (car prefix) (car remaining))
                        (walk (cdr remaining) (cdr prefix))))))))

    ;; ─── The command (pure) ─────────────────────────────────────────
    ;;
    ;; WORKTREE → the shell command that asks for its live leaf.
    ;;
    ;; `pick` takes no directory argument: it walks UP from the current
    ;; directory to find the enclosing working tree, so the `cd` is how
    ;; the worktree is named at all. `cd` is guarded rather than assumed
    ;; — a stale path from an editor's stored window state is an ordinary
    ;; occurrence — and a failed `cd` short-circuits the `&&`, so the
    ;; miss arrives as empty stdout like every other miss rather than as
    ;; `pick` answering about Modaliser's own directory. That last part
    ;; is the reason for the `&&`: without it, a bad `cd` would leave the
    ;; CLI running wherever the shell started and confidently return the
    ;; WRONG grove's leaf.
    (define (live-leaf-command worktree)
      (string-append tool-path-prefix
                     "unset GROVE_SIGNAL_FILE; "
                     "cd '" (sq-escape worktree) "' 2>/dev/null"
                     " && grove-llm pick 2>/dev/null"))

    ;; ─── Reading the answer (pure) ──────────────────────────────────
    ;;
    ;; OUT → the leaf path, or #f. `pick` prints one absolute path and a
    ;; newline on success and nothing at all otherwise, so this is a trim
    ;; and an emptiness test — but it takes the FIRST line rather than
    ;; the trimmed whole, so that a future verb (or a shell that leaks a
    ;; warning onto stdout) degrades to a wrong-but-single path rather
    ;; than to a two-line string no `code` invocation could open.
    (define (leaf-of-output out)
      (let ((first (string-trim (car (string-split out "\n")))))
        (if (string=? first "") #f first)))

    ;; ─── The impure edge ────────────────────────────────────────────

    ;; WORKTREE → its live grove leaf's absolute path, or #f. A worktree
    ;; that is not a string, or is empty, is #f without spawning: the
    ;; caller resolving "which folder is this window rooted at" may
    ;; itself have failed, and that failure should not become a `cd ''`.
    (define (live-leaf worktree)
      (and (string? worktree)
           (not (string=? worktree ""))
           (leaf-of-output (run-shell (live-leaf-command worktree)))))))
