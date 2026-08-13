import Testing
@testable import Modaliser

/// The seam under test is the **encoding**, never the posting. Nothing here
/// calls `MediaKeyEmitter.send` — that would toggle the developer's own music,
/// which is exactly the outward leak ADR-0023 makes structurally impossible for
/// the rest of the suite. The pure `data1(button:state:)` carries all the
/// arithmetic worth protecting.
@Suite("MediaKeyEmitter")
struct MediaKeyEmitterTests {

    // MARK: - Button constants (NX_KEYTYPE_*, ev_keymap.h)

    /// Pinned against the SDK header so a well-meaning renumber fails loudly.
    /// `next`/`previous` are FAST/REWIND, *not* NX_KEYTYPE_NEXT 17 /
    /// NX_KEYTYPE_PREVIOUS 18 — see the reasoning on `MediaKeyEmitter.Button`.
    @Test func buttonRawValuesMatchEvKeymapHeader() {
        #expect(MediaKeyEmitter.Button.playPause.rawValue == 16)   // NX_KEYTYPE_PLAY
        #expect(MediaKeyEmitter.Button.next.rawValue == 19)        // NX_KEYTYPE_FAST
        #expect(MediaKeyEmitter.Button.previous.rawValue == 20)    // NX_KEYTYPE_REWIND
        #expect(MediaKeyEmitter.Button.volumeUp.rawValue == 0)     // NX_KEYTYPE_SOUND_UP
        #expect(MediaKeyEmitter.Button.volumeDown.rawValue == 1)   // NX_KEYTYPE_SOUND_DOWN
        #expect(MediaKeyEmitter.Button.mute.rawValue == 7)         // NX_KEYTYPE_MUTE
    }

    /// NX_KEYDOWN 10 / NX_KEYUP 11, from IOLLEvent.h.
    @Test func buttonStateRawValuesMatchIOLLEventHeader() {
        #expect(MediaKeyEmitter.ButtonState.down.rawValue == 0xA)
        #expect(MediaKeyEmitter.ButtonState.up.rawValue == 0xB)
    }

    /// NX_SUBTYPE_AUX_CONTROL_BUTTONS, from IOLLEvent.h.
    @Test func subtypeIsAuxControlButtons() {
        #expect(MediaKeyEmitter.auxControlButtonsSubtype == 8)
    }

    // MARK: - data1 bit packing

    /// The arithmetic spelled out three ways — literal, shifted, and OR'd — so
    /// an edit to either shift width fails on a concrete number rather than on
    /// a restatement of the implementation.
    @Test func playPauseDownPacksIntoData1() {
        let packed = MediaKeyEmitter.data1(button: .playPause, state: .down)
        #expect(packed == 1048576 | 2560)
        #expect(packed == (16 << 16) | (0xA << 8))
        #expect(packed == 1051136)
    }

    @Test func playPauseUpPacksIntoData1() {
        let packed = MediaKeyEmitter.data1(button: .playPause, state: .up)
        #expect(packed == (16 << 16) | (0xB << 8))
        #expect(packed == 1051392)
    }

    /// Volume up is button 0, so its whole payload is the state nibble — the
    /// case that would silently pass if the button shift were dropped.
    @Test func volumeUpIsButtonZeroSoOnlyStateShows() {
        #expect(MediaKeyEmitter.data1(button: .volumeUp, state: .down) == 0xA << 8)
        #expect(MediaKeyEmitter.data1(button: .volumeUp, state: .down) == 2560)
    }

    @Test func everyButtonRoundTripsOutOfData1() {
        for button in MediaKeyEmitter.Button.allCases {
            let packed = MediaKeyEmitter.data1(button: button, state: .down)
            #expect((packed >> 16) & 0xFFFF == button.rawValue)
            #expect((packed >> 8) & 0xFF == MediaKeyEmitter.ButtonState.down.rawValue)
        }
    }

    /// The low byte is the repeat count; a synthesised press is never a repeat.
    @Test func repeatBitsAreAlwaysClear() {
        for button in MediaKeyEmitter.Button.allCases {
            for state in [MediaKeyEmitter.ButtonState.down, .up] {
                #expect(MediaKeyEmitter.data1(button: button, state: state) & 0xFF == 0)
            }
        }
    }

    @Test func downAndUpDifferOnlyInTheStateNibble() {
        for button in MediaKeyEmitter.Button.allCases {
            let down = MediaKeyEmitter.data1(button: button, state: .down)
            let up = MediaKeyEmitter.data1(button: button, state: .up)
            #expect(up - down == 1 << 8)
        }
    }

    // MARK: - Scheme-facing names

    @Test func schemeNamesAreTheSixDocumentedButtons() {
        #expect(MediaKeyEmitter.Button.allNames
                == ["play-pause", "next", "previous", "volume-up", "volume-down", "mute"])
    }

    @Test func everyNameResolvesBackToItsButton() {
        for button in MediaKeyEmitter.Button.allCases {
            #expect(MediaKeyEmitter.Button.named(button.schemeName) == button)
        }
    }

    /// No aliases and no case folding: the Scheme surface takes a symbol, and
    /// symbols are compared as written.
    @Test func unknownOrMisspelledNamesResolveToNil() {
        #expect(MediaKeyEmitter.Button.named("playpause") == nil)
        #expect(MediaKeyEmitter.Button.named("play_pause") == nil)
        #expect(MediaKeyEmitter.Button.named("Play-Pause") == nil)
        #expect(MediaKeyEmitter.Button.named("volume") == nil)
        #expect(MediaKeyEmitter.Button.named("") == nil)
    }
}
