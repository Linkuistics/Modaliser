# media-key-k2

## Goal

Add a **Media key** emitter to `(modaliser input)` and bind `p` "Play/Pause"
at the top level of the shipped `default-config.scm`'s `'global` screen.
Everything verifiable offline lands here; the live proof is `local-install-k3`.

## Context

Read `Sources/Modaliser/KeystrokeEmitter.swift` first — it is the sibling
emitter, and the thing to notice is that every path in it posts a *virtual
keycode* via `CGEvent(keyboardEventSource:virtualKey:keyDown:)`. Media buttons
have no virtual keycode, so none of that machinery is reusable and the
named-key table is the wrong place for this (`CONTEXT.md`, **Media key**).

The event shape is `NSEvent.otherEvent(with: .systemDefined, …)`, subtype `8`
(`NX_SUBTYPE_AUX_CONTROL_BUTTONS`), with the button and its up/down state
bit-packed into `data1` as `(button << 16) | (state << 8)` — state `0xA` for
down, `0xB` for up — then bridged with `.cgEvent` and posted. Button constants
come from `IOKit/hidsystem/ev_keymap.h`: `NX_KEYTYPE_PLAY` 16, `NX_KEYTYPE_FAST`
19, `NX_KEYTYPE_REWIND` 20, `NX_KEYTYPE_SOUND_UP` 0, `NX_KEYTYPE_SOUND_DOWN` 1,
`NX_KEYTYPE_MUTE` 7.

**Those numbers are from this session's reading, not from a source that was
opened.** `driving.md`'s cite-to-the-source rule applies squarely: verify each
against `ev_keymap.h` on this machine (it ships inside the SDK — find it under
`$(xcrun --show-sdk-path)/usr/include/IOKit/hidsystem/ev_keymap.h`) or Apple's
own documentation, and leave the citation in a comment beside the table. If a
constant cannot be verified, say so in the comment rather than shipping quiet
confidence.

Three facts that shape the implementation:

- **This event never re-enters our own tap.** `KeyboardCapture.start()` builds
  its `eventMask` from `keyDown | keyUp` only, so an `NSSystemDefined` event is
  not in the mask. Do **not** tag it with `KeyboardCapture.reInjectionMagic` —
  that tag exists to get synthetic *keystrokes* back past our tap, and there is
  nothing here to get past.
- **`(modaliser input)` is not quarantined.** It carries no `-native` suffix and
  `apps/dia.sld`, `apps/iterm.sld` and `muxes/herdr.sld` already import it, so
  the portable tree may reach this primitive directly. `check-portable-surface.sh`
  has nothing to say about it — but run it anyway.
- **ADR-0021 divides the work.** The emitter and the six button names are a
  **Facility** and belong in Swift plus its Scheme surface. The key `p` and the
  label "Play/Pause" are a **Decision** and may appear *only* in
  `default-config.scm`. `check-decision-free.sh` runs at strict zero.

## Done when

- `(modaliser input)` exports `send-media-key`, taking a symbol from
  `play-pause`, `next`, `previous`, `volume-up`, `volume-down`, `mute`, and
  raising a decodable error naming the offender on anything else.
- `default-config.scm`'s `'global` screen binds `p` "Play/Pause" as a **Terminal**
  key (no `'next`) at its **top level** — a loose row, beside "Highlight Cursor",
  not inside the Applications or Search panel.
- `docs/reference/libraries.md` documents it in the `(modaliser input)` section
  (~line 1161) *and* in the summary table (~line 1262) — the table is a
  roll-up and a finding against the section does not reach it
  (`driving.md`, "by structural level"). Check whether
  `docs/reference/keyboard.md` also needs a line.
- `swift test`, `./scripts/check-portable-surface.sh` and
  `./scripts/check-decision-free.sh` are all green.

## Notes

**The test seam is the encoding, not the posting** — and this is the one thing
to get right. A test that actually posted the event would toggle the
developer's own music, which is precisely the class of outward leak ADR-0023
exists to prevent; the suite reaches nothing outside the process and that is
structural, not per-test discipline. So split a pure, total function —
button symbol/name → `data1` for a given up/down state — from the impure
`post`, and test only the pure half, in `Tests/ModaliserTests/`. Assert the
bit-packing arithmetic explicitly (`play-pause` down is `(16 << 16) | (0xA << 8)`
= `1048576 | 2560`), so a future edit to the shift widths fails loudly.
`KeystrokeEmitterTests.swift` and `InputLibraryTests.swift` are the files to
mirror.

Emit the **down and up pair**, not a lone down. A single down is widely
reported to work with some receivers and to be ignored by others; the pair is
what real hardware produces and costs one extra post.

The five unbound buttons are intentional — the library ships the family, the
config binds one key (root brief, "Notes"). Do not bind the others here.

`p` is confirmed unbound at the `'global` top level in `default-config.scm`;
`local-install-k3` will confirm the same for the user's own config.
