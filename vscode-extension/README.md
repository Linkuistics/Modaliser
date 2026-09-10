# Modaliser Companion

A small peer that runs inside each VSCode window and answers Modaliser's
questions about what is open in it, over a Unix-domain socket.

This is not a general-purpose extension and does nothing on its own. It exists
because VSCode's extension API carries what is open *inside* a window —
`window.terminals`, `window.tabGroups` — and nothing reachable from outside
VSCode does. Reading a *rendering* of that state through the accessibility
tree was designed, reviewed and rejected on what the rendering costs; the
reasoning is in Modaliser's own `docs/adr/0026-…` and
`docs/specs/vscode-window-parts.md`, and this README does not repeat it.

## Install

From the Modaliser repository root:

```sh
./scripts/install-vscode-extension.sh
```

Then **restart VSCode** — it scans `~/.vscode/extensions` at startup.

It is a separate step from installing Modaliser on purpose: it targets a
different application, needs that application present, and upgrades on its own
cadence. Nothing fails a Modaliser build if this extension goes stale, so the
`parts` reply carries a protocol version and Modaliser answers a mismatch with
an empty panel and a log line rather than by interpreting fields whose meaning
is not agreed.

## What it exposes, exactly

Three methods, and the set is the security surface — a
`commands.executeCommand` passthrough is one line and would turn this into a
remote control for the workbench, so it is not here and does not become here
without a recorded decision.

| method | shape | answer |
|---|---|---|
| `parts` | `{}` | the window's terminals and editor tabs, with a token each |
| `focus-terminal` | `{"token": N}` | **nothing** |
| `focus-editor` | `{"token": N}` | **nothing** |

Newline-delimited JSON, one `{"id","method","params"}` message per connection.
The two focus methods are *notifications*: nothing comes back, and a refusal
therefore leaves no trace on the wire — the **Modaliser Companion** output
channel is where a refused press says why.

An action is refused, silently, when this window is not focused, when the
token names nothing, when it names a part that has since closed, or when it
names the other kind of part.

## Where it lives on disk

```
~/.config/modaliser/vscode/            mode 0700
  vs-<time>-<pid>-<rand>.sock          one per extension instance
  focused                              the socket path of the focused window
```

A socket name is never reused, because Modaliser addresses an action as *a
socket path plus a token* and a path back in service under a new instance
would be an address that outlived what it addressed. Crashed hosts therefore
leave files behind, and each activation sweeps the ones whose connect is
refused.

## Development

```sh
npm install
npm test        # tsc, then node --test
npm run watch
```

Everything with behaviour in it is written against the `PeerEnv` interface in
`src/peerEnv.ts` and tested against fakes; `src/extension.ts` is the only
module that imports `vscode` at runtime. That is what makes the tests worth
having, so keep decisions out of `extension.ts`.

The tab-kind classifier takes the `vscode` namespace as an *argument* for the
same reason: the kinds are runtime classes, `instanceof` is the only way to
tell them apart, and importing the module would have made the per-kind
activation table — the part of this design most likely to be wrong — the one
part no test could reach.

**What no test here can reach.** Every test asserts the *call*; none asserts
the *effect*, because the effect is VSCode's. Two cases have to be driven by
hand against a real window, because a fake passes them and a real window can
fail them: the same file open in two editor groups with the groups reordered
(each row must activate its own tab), and a preview tab that is already active
(pressing its label must change nothing, not pin it).
