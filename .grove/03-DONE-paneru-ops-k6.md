# paneru-ops-k6

**Kind:** impl

## Goal

Build `Sources/Modaliser/Scheme/lib/modaliser/wms/paneru.sld`: the seven ops and
the installation predicate. First code in the workstream, and the smaller half —
the listing is `paneru-strip-list-k7`.

## Context

Build to `docs/specs/paneru-window-management.md` (from `paneru-design-k3`); it
settles the exported surface. The ops themselves are fixed by paneru's CLI:

| op | wire form |
|---|---|
| focus west / east | `window focus west` \| `window focus east` |
| swap west / east | `window swap west` \| `window swap east` |
| grow / shrink | `window grow` \| `window shrink` |
| center | `window center` |

All space-separated after `send-cmd` — **not** the underscored `paneru.toml`
binding spelling. Every call goes through `(modaliser shell)`'s `run-shell`
(ADR-0023), never the native shell library, and the file must not import any
`…-native` library or `(lispkit …)` — including in prose comments, where the
literal parenthesised forms are what the check script greps for.

The installation predicate is `command -v paneru` through the ADR-0017 derived
tool path, matching how existing backends probe. It answers *installed*, never
*running* — see the root brief and the glossary's **Paneru-installed
composition**.

## Done when

- The library exists at the agreed path, exporting seven ops and the predicate.
- Tests assert the **exact command string** each op sends, via a canned
  `current-shell-runner` — that string is the thing most likely to be wrong, and
  the only place the wire format is pinned.
- A test covers the predicate answering both ways.
- `./scripts/check-portable-surface.sh` and `./scripts/check-decision-free.sh`
  both pass — the latter matters here: this file authors **no key and no label**.
- `swift test` green, and still reaching nothing outside the process.

## Notes

`wms/` is a new directory. Check whether anything enumerates library
subdirectories (`build-app.sh` bundling, the `sys/` mirror, the check scripts)
and needs to learn about it — a new category has not been added in a while, so
do not assume the tree is discovered generically.
