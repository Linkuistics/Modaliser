import AppKit

/// Emits synthetic **media key** presses — play/pause, track skip, volume —
/// via `NSSystemDefined` subtype-8 events.
///
/// Deliberately *not* part of `KeystrokeEmitter`: media buttons have no virtual
/// keycode, so none of that emitter's `CGEvent(keyboardEventSource:virtualKey:)`
/// machinery applies and the named-key table is the wrong home for them
/// (`CONTEXT.md`, **Media key**). The event goes to whichever client holds the
/// system's Now Playing role — generally *not* the frontmost app, and not
/// queryable (`CONTEXT.md`, **Now Playing target**).
///
/// The pure/impure split is the test seam: `data1(button:state:)` is total and
/// tested; `send` posts and is not. A test that posted would toggle the
/// developer's own music, which is the class of outward leak ADR-0023 exists to
/// prevent.
enum MediaKeyEmitter {

    /// A media button, by its `NX_KEYTYPE_*` special-key number.
    ///
    /// Raw values verified against `ev_keymap.h` in the macOS SDK on 2026-08-13
    /// (`$(xcrun --show-sdk-path)/System/Library/Frameworks/IOKit.framework/`
    /// `Versions/A/Headers/hidsystem/ev_keymap.h` — note it is *not* under
    /// `usr/include/IOKit/`, where the task brief expected it).
    ///
    /// **`next`/`previous` are a judgement call, not a lookup.** The same header
    /// also defines `NX_KEYTYPE_NEXT` 17 and `NX_KEYTYPE_PREVIOUS` 18, and both
    /// pairs appear in `NX_SPECIALKEY_POST_MASK`, so the header cannot say which
    /// a Now Playing client honours. `FAST`/`REWIND` are chosen because that is
    /// what an Apple keyboard's track-skip keys emit — a claim from prior
    /// knowledge, *not* verified from any source on this machine. Only
    /// `play-pause` is bound by the shipped config and proven live; if
    /// `next`/`previous` ever turn out inert, 17/18 is the first thing to try.
    enum Button: Int, CaseIterable {
        case playPause  = 16   // NX_KEYTYPE_PLAY
        case next       = 19   // NX_KEYTYPE_FAST
        case previous   = 20   // NX_KEYTYPE_REWIND
        case volumeUp   = 0    // NX_KEYTYPE_SOUND_UP
        case volumeDown = 1    // NX_KEYTYPE_SOUND_DOWN
        case mute       = 7    // NX_KEYTYPE_MUTE

        /// The symbol Scheme names this button by, e.g. `'play-pause`.
        /// Single source of truth: `named(_:)` and `allNames` both derive from
        /// it, so a new button cannot arrive half-named.
        var schemeName: String {
            switch self {
            case .playPause:  return "play-pause"
            case .next:       return "next"
            case .previous:   return "previous"
            case .volumeUp:   return "volume-up"
            case .volumeDown: return "volume-down"
            case .mute:       return "mute"
            }
        }

        /// The button a Scheme symbol names, or nil if it names none.
        static func named(_ name: String) -> Button? {
            allCases.first { $0.schemeName == name }
        }

        /// Every accepted name, in declaration order — the error message's
        /// enumeration, so a rejection always lists the current truth.
        static var allNames: [String] { allCases.map(\.schemeName) }
    }

    /// Up/down state of a media button press, as packed into `data1`.
    /// Values verified against `IOLLEvent.h` (same SDK `hidsystem` directory):
    /// `NX_KEYDOWN` 10, `NX_KEYUP` 11.
    enum ButtonState: Int {
        case down = 0xA
        case up   = 0xB
    }

    /// `NX_SUBTYPE_AUX_CONTROL_BUTTONS`, verified in `IOLLEvent.h` — the
    /// `NSSystemDefined` subtype that carries a special-key press.
    static let auxControlButtonsSubtype: Int16 = 8

    /// The `data1` payload for one button in one state.
    ///
    /// **The one thing here that no local source proves.** The header block
    /// documenting `NX_SUBTYPE_AUX_CONTROL_BUTTONS` in `IOLLEvent.h` actually
    /// describes `NX_SUBTYPE_AUX_MOUSE_BUTTONS`' `misc.L[]` layout instead — an
    /// SDK documentation bug — so this packing is long-standing convention
    /// rather than published contract, and it is what a live press has to
    /// confirm. The low byte (repeat count) stays 0: a synthesised press is
    /// never a key repeat.
    static func data1(button: Button, state: ButtonState) -> Int {
        (button.rawValue << 16) | (state.rawValue << 8)
    }

    /// Post a complete press: down then up.
    ///
    /// The pair is deliberate. A lone down is honoured by some Now Playing
    /// clients and ignored by others, whereas the pair is what real hardware
    /// produces and costs one extra post.
    ///
    /// Unlike `KeystrokeEmitter`, these events are **not** tagged with
    /// `KeyboardCapture.reInjectionMagic`. That tag exists to get synthetic
    /// *keystrokes* back past our own tap; `KeyboardCapture.start()` builds its
    /// mask from `keyDown | keyUp` only, so an `NSSystemDefined` event never
    /// reaches the tap and has nothing to get past.
    static func send(_ button: Button) {
        post(button, state: .down)
        post(button, state: .up)
    }

    private static func post(_ button: Button, state: ButtonState) {
        guard let event = NSEvent.otherEvent(with: .systemDefined,
                                             location: .zero,
                                             modifierFlags: [],
                                             timestamp: 0,
                                             windowNumber: 0,
                                             context: nil,
                                             subtype: auxControlButtonsSubtype,
                                             data1: data1(button: button, state: state),
                                             data2: -1) else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
