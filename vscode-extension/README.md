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

This extension ships **inside** `Modaliser.app`, and Modaliser copies it into
`~/.vscode/extensions` only when you ask it to and confirm — never on its own
initiative. Asking is a row on your VSCode screen, bound in your own
`config.scm`; Modaliser's `examples/vscode.scm` ships it as **Install VSCode
Companion**. Press it, confirm the dialog, then **restart VSCode** — it scans
`~/.vscode/extensions` at startup only, so the press that installs the
extension can never be the press that uses it.

The row hides itself once the version your Modaliser ships is installed, and
comes back when a Modaliser upgrade ships a newer one.

Two consequences worth stating plainly. This is **extension code**, which
VSCode then activates in every window it opens. And uninstalling Modaliser
does *not* remove it — `brew uninstall --zap modaliser`, or deleting the
directory by hand, is what takes it away.

Installing it this way means its upgrade cadence is Modaliser's: an
extension-only fix needs a Modaliser release. The `parts` reply still carries a
protocol version, and Modaliser answers a mismatch with an empty panel and a
log line rather than by interpreting fields whose meaning is not agreed — a
hand-installed or disabled copy is still an ordinary condition.

From a source checkout, `./scripts/install-vscode-extension.sh` builds this
directory and installs it directly, which is the loop to work in when you are
editing `src/`. It is the developer's path; it is not how a released Modaliser
reaches a user's machine.

## What it exposes, exactly

Four methods, and the set is the security surface — a
`commands.executeCommand` passthrough is one line and would turn this into a
remote control for the workbench, so it is not here and does not become here
without a recorded decision.

| method | shape | answer |
|---|---|---|
| `parts` | `{}` | the window's terminals and editor tabs, with a token each |
| `focus-terminal` | `{"token": N}` | **nothing** |
| `focus-editor` | `{"token": N}` | **nothing** |
| `close-editor-if-missing` | `{"token": N}` | **nothing** |

Newline-delimited JSON, one `{"id","method","params"}` message per connection.
The three action methods are *notifications*: nothing comes back, and a refusal
therefore leaves no trace on the wire — the **Modaliser Companion** output
channel is where a refused press says why.

An action is refused, silently, when this window is not focused, when the
token names nothing, when it names a part that has since closed, or when it
names the other kind of part.

Browser, webview, diff and other resource-less tabs are selectable too. Their
tokens resolve to live tabs; the peer visits existing groups as needed and
selects the tab's current index. This preserves the existing tab rather than
opening a new browser or comparison. Focus and membership are rechecked after
each group command; a concurrent change during the final host command remains
a race because VSCode exposes no atomic tab-reveal API.

`close-editor-if-missing` additionally requires a clean local `file` text or
custom tab. It checks the live backing URI with `workspace.fs.stat` and closes
only on `FileSystemError.FileNotFound`, preserving focus. Existing resources,
permission/provider errors, virtual resources, notebooks and diffs stay open.
Focus, membership, input identity and dirty state are checked again after the
lookup. Ordinary host dirty-close protection still applies; no save or discard
operation is exposed.

This operation requires companion **1.1.0**. Protocol 1's existing fields and
methods retain their meanings; an older companion simply cannot clean tabs.
After upgrading Modaliser, use **Install VSCode Companion** and restart VSCode.
To adopt Grove cleanup, copy the updated “Grove Leaf” composition and its imports
from the mirrored `examples/vscode.scm` into your own config. Shipping facilities
does not rewrite an existing user config. Cleanup is attempted before live-leaf
lookup, including when the grove is finished or its directory was removed;
reveal and its explorer follow-up remain independent of cleanup success.

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
