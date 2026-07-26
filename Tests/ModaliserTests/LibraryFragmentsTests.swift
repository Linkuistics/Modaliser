import Foundation
import Testing
import LispKit
@testable import Modaliser

// The library constructors of the configuration-value model
// (library-fragments-k11, docs/specs/configuration-value.md "The
// Terminal context map", ADR-0013): iterm:wiring as a terminal-like
// host fragment whose backend record carries the 'canvas-frame host
// capability; herdr:wiring / nvim:wiring / tmux:wiring / zellij:wiring
// as Terminal-context-map entries carrying their own
// wiring. The worked-example composition —
//
//   (configuration (iterm:wiring) (screen 'com.googlecode.iterm2 …)
//                  (terminal-contexts (herdr:wiring) (nvim:wiring))
//                  (screen 'herdr …) (screen 'nvim …)
//                  (tree 'herdr-panes-focus …))
//
// — must resolve activation for iTerm-alone and iTerm+herdr chains,
// lower to a closed graph, and expose chip geometry's host frame
// through the façade capability.
//
// Both halves of that shape are ADR-0021: each library ships the WIRING
// (backend record, digit-jump tree, and for a mux the context entry)
// and the composition authors the SCREEN, which is why `cfg` below
// carries a (screen 'com.googlecode.iterm2 …) and a (screen 'herdr …)
// of its own. Both are deliberately small — the closure the wiring
// needs, not a replica of the seeded stock composition, which
// `ConfigDslTests.defaultConfigSchemeLoadsWithoutErrors` covers.
//
// The iTerm screen is also what makes the host terminal-like: its scope
// must be the backend record's match-key, or activation never consults
// the context map and the two chain tests below fail.
@Suite("Library fragments (host and inner-tool `wiring` constructors)")
struct LibraryFragmentsTests {

    private func loaded() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser util)
                  (modaliser fsm)
                  (modaliser configuration)
                  (modaliser terminal)
                  (modaliser activation)
                  (modaliser fsm)
                  (modaliser dsl)
                  (prefix (modaliser apps iterm) iterm:)
                  (prefix (modaliser apps kitty) kitty:)
                  (prefix (modaliser apps wezterm) wezterm:)
                  (prefix (modaliser apps ghostty) ghostty:)
                  (prefix (modaliser apps alacritty) alacritty:)
                  (prefix (modaliser muxes herdr) herdr:)
                  (prefix (modaliser muxes tmux) tmux:)
                  (prefix (modaliser muxes zellij) zellij:)
                  (prefix (modaliser tools nvim) nvim:)
                  (only (modaliser blocks herdr-list) herdr-grid-host-frame))
        """)
        try engine.evaluate("""
          (define (frame sym fg) (cons sym (vector 'pane "p" 'fg fg)))
        """)
        // The worked-example composition (the leaf's Done-when shape).
        try engine.evaluate("""
          (define cfg
            (configuration
              (tree 'global (group "" "Global" (key "g" "G" (lambda () 'g))))
              (iterm:wiring)
              ;; The composition's own iTerm screen (ADR-0021). The scope
              ;; is machinery — it is the backend record's match-key, and
              ;; what makes the screen terminal-like.
              (screen 'com.googlecode.iterm2
                (key "z" "Toggle Zoom" iterm:toggle-pane-zoom)
                (key "C-I" "Configure iTerm" iterm:configure!
                     'hidden iterm:configured?)
                (panel "Panes" (iterm:pane-list-block 'chips? #t)))
              (terminal-contexts (herdr:wiring) (nvim:wiring))
              ;; nvim's wiring is a context entry and nothing else — no
              ;; backend record (it hosts no panes), and no screen, so
              ;; the composition authors this one for the entry to
              ;; resolve to.
              (screen 'nvim
                'display-name "Neovim"
                (key "h" "Focus Left" nvim:focus-window-left 'next 'self))
              ;; The composition's own herdr screen (ADR-0021). The scope
              ;; symbols are machinery — herdr:wiring's context entry
              ;; names 'herdr, and the Focus row crosses into
              ;; 'herdr-panes-focus — so both must exist for the value to
              ;; lower closed. Everything else here is preference.
              (screen 'herdr
                'display-name "herdr"
                'provider herdr:herdr-jump-provider
                'on-enter herdr:paint-jump-chips!
                'on-leave herdr:clear-jump-chips!
                (key "c" "Copy Mode"  (herdr:copy-mode-op  herdr:herdr-default-prefix))
                (key "C" "Scrollback" (herdr:scrollback-op herdr:herdr-default-prefix))
                (open "P" "Panes"
                  (panel "Focus"
                    (key "h" "Left" herdr:focus-pane-left 'next 'herdr-panes-focus))
                  (panel "Panes" (herdr:pane-list-block 'chips? #t)))
                (panel "Jump" (herdr:jump-legend-block)))
              (tree 'herdr-panes-focus
                (tree-root 'herdr-panes-focus
                  'exit-on-unknown #t 'display-name "Focus"
                  (key "h" "Left" herdr:focus-pane-left 'next 'self)))))
        """)
        return engine
    }

    // MARK: - The worked-example composition resolves activation

    @Test func itermAloneChainLandsOnTheItermScreen() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (equal? (resolve-activation 'local "com.googlecode.iterm2"
                    (list (frame 'iterm "zsh")) cfg)
                  '((root . "com.googlecode.iterm2") (stack)))
        """) == .true)
    }

    @Test func itermPlusHerdrChainLandsOnHerdrSeedingTheHostFrame() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (equal? (resolve-activation 'local "com.googlecode.iterm2"
                    (list (frame 'iterm "herdr") (frame 'herdr "zsh")) cfg)
                  '((root . "herdr") (stack "com.googlecode.iterm2")))
        """) == .true)
    }

    // The chain frame carries the full foreground COMMAND LINE; the map
    // is keyed by exe name (ADR-0013), so the consult must normalize —
    // both an argument tail and an absolute path.
    @Test func fgCommandLineNormalizesToItsExeForTheMapConsult() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (equal? (resolve-activation 'local "com.googlecode.iterm2"
                    (list (frame 'iterm "nvim README.md")) cfg)
                  '((root . "nvim") (stack "com.googlecode.iterm2")))
        """) == .true)
        #expect(try engine.evaluate("""
          (equal? (resolve-activation 'local "com.googlecode.iterm2"
                    (list (frame 'iterm "/opt/homebrew/bin/nvim")) cfg)
                  '((root . "nvim") (stack "com.googlecode.iterm2")))
        """) == .true)
    }

    // MARK: - The composed value lowers closed

    // The strongest structural assertion: every authored reference in
    // every constructor-built tree — walk cross ids, the herdr Focus
    // panel's 'next 'herdr-panes-focus, the context entries' tree and
    // backend keys — resolves. A dangling id anywhere raises here.
    @Test func workedExampleValueLowersToAClosedGraph() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (fsm-graph? (lower-with-activation cfg (lambda () '())))
        """) == .true)
    }

    // The other two muxes, composed the same way: each `wiring` brings a
    // context entry + backend + digit-jump tree, and the composition
    // brings the screen the entry names. Dropping either screen makes
    // this a dangling reference, which is exactly the load-time error
    // that keeps the machinery/preference split honest (ADR-0021).
    @Test func muxWiringsComposeAndLowerClosedToo() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (fsm-graph?
            (lower-with-activation
              (configuration
                (tree 'global (group "" "Global" (key "g" "G" (lambda () 'g))))
                (iterm:wiring)
                (screen 'com.googlecode.iterm2
                  (key "z" "Toggle Zoom" iterm:toggle-pane-zoom))
                (terminal-contexts (tmux:wiring) (zellij:wiring))
                (screen 'tmux
                  (key "h" "Focus Left"  tmux:focus-pane-left 'next 'self)
                  (key "z" "Toggle Zoom" tmux:toggle-pane-zoom))
                (screen 'zellij
                  (key "h" "Focus Left"  zellij:focus-pane-left 'next 'self)
                  (key "z" "Toggle Zoom" zellij:toggle-pane-zoom)))
              (lambda () '())))
        """) == .true)
    }

    // The other host apps' fragments: backend record (+ digit-jump mode
    // tree where the host has pane ops; alacritty is detection-only) —
    // no stock screen, so the composition supplies its own. The whole
    // set merges and lowers together.
    @Test func otherHostFragmentsComposeBackendsAndDigitTrees() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (let ((host-cfg (configuration
                            (kitty:fragment) (wezterm:fragment)
                            (ghostty:fragment) (alacritty:fragment))))
            (and (terminal-backend? (configuration-backend-ref host-cfg 'kitty))
                 (terminal-backend? (configuration-backend-ref host-cfg 'wezterm))
                 (terminal-backend? (configuration-backend-ref host-cfg 'ghostty))
                 (terminal-backend? (configuration-backend-ref host-cfg 'alacritty))
                 (pair? (configuration-tree-ref host-cfg 'kitty-pane-digit))
                 (pair? (configuration-tree-ref host-cfg 'wezterm-pane-digit))
                 (pair? (configuration-tree-ref host-cfg 'ghostty-pane-digit))
                 (fsm-graph? (lower-configuration host-cfg))))
        """) == .true)
    }

    // MARK: - The 'canvas-frame host capability

    @Test func itermWiringBackendCarriesTheCanvasFrameCapability() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (procedure?
            (terminal-backend-capability
              (configuration-backend-ref cfg 'iterm) 'canvas-frame))
        """) == .true)
    }

    // Chip geometry's host-frame source consults the FRONTMOST host
    // backend's capability through the façade: a stub host carrying a
    // canned canvas-frame probe answers herdr-list's calibrated
    // host-frame lookup end-to-end — no iTerm, no AX.
    @Test func chipGeometryReadsTheHostCapabilityThroughTheFacade() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (begin
            (terminal-install-backends! (list
              (make-terminal-backend 'stubhost "Stub" 'host "com.test.stub" #f
                (lambda () #f) (lambda () "p0")
                #f #f #f #f #f #f #f #f #f #f #f #f
                #f #f
                (lambda () #t)
                (list (cons 'canvas-frame
                            (lambda (total-w total-h)
                              (list (cons 'x 10) (cons 'y 20)
                                    (cons 'w (* total-w 8))
                                    (cons 'h (* total-h 18)))))))))
            (parameterize ((current-frontmost-bundle-id
                             (lambda () "com.test.stub")))
              (equal? (herdr-grid-host-frame 40 10)
                      '((x . 10) (y . 20) (w . 320) (h . 180)))))
        """) == .true)
    }

    // A host without the capability — including any record built through
    // the pre-capability 23-argument constructor shape — degrades to no
    // frame (chips skip), never an error.
    @Test func capabilityLessHostDegradesToNoFrame() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (begin
            (terminal-install-backends! (list
              (make-terminal-backend 'barehost "Bare" 'host "com.test.bare" #f
                (lambda () #f) (lambda () "p0")
                #f #f #f #f #f #f #f #f #f #f #f #f
                #f #f
                (lambda () #t))))
            (parameterize ((current-frontmost-bundle-id
                             (lambda () "com.test.bare")))
              (and (not (host-capability 'canvas-frame))
                   (not (herdr-grid-host-frame 40 10)))))
        """) == .true)
    }

    // MARK: - Fragment shape

    // ADR-0021's line, read off the fragment itself: (herdr:wiring)
    // contributes the context entry, the backend record and the
    // machinery-named digit-jump tree — and NO tree under 'herdr. That
    // absence is the contract, not an omission: the screen the entry
    // resolves to is the composition's to author, so a library change
    // can never silently re-take a key the user chose.
    @Test func herdrWiringCarriesIntegrationAndNoScreen() throws {
        let engine = try loaded()
        try engine.evaluate("(define w (configuration (herdr:wiring)))")
        #expect(try engine.evaluate("""
          (and (equal? (configuration-context-ref w "herdr")
                       '((tree . herdr) (backend . herdr)))
               (terminal-backend? (configuration-backend-ref w 'herdr))
               (pair? (configuration-tree-ref w 'herdr-pane-digit))
               ;; The two the composition must supply.
               (not (configuration-tree-ref w 'herdr))
               (not (configuration-tree-ref w 'herdr-panes-focus)))
        """) == .true)
    }

    // The context map entry itself: exe → tree (+ backend for herdr;
    // tree-only for nvim).
    @Test func contextEntriesReferenceTreeAndBackendByKey() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (equal? (configuration-context-ref cfg "herdr")
                  '((tree . herdr) (backend . herdr)))
        """) == .true)
        #expect(try engine.evaluate("""
          (equal? (configuration-context-ref cfg "nvim")
                  '((tree . nvim)))
        """) == .true)
    }
}
