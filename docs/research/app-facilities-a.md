# Separating app-control facilities from user composition — survey (a)

Exploratory research for `configuration-exploration`. External sources consulted
**2026-09-10**, paraphrased unless the wording carries the claim. The inspected
revision is **`b5886f81`**, this grove's parent.

A survey, not a decision. ADR-0021 is the baseline being extended, not a proposal
being made. Nothing here authorises implementation, a plugin format, or an
install.

| Mark | Meaning |
|---|---|
| **[src]** | Read out of this repository at the revision above; file and line given. |
| **[doc]** | A dated primary external source, linked at the claim. |
| **[inf]** | Derived from **[src]** + **[doc]**. Sound, unobserved. |
| **[gap]** | Not established: no primary source found, or it needs an experiment. |

Nothing was built, loaded, timed or measured.

---

## 1. The VS Code example, split down the middle

`examples/vscode.scm` is the workstream's test case, and tracing it shows the
ADR-0021 line already falling in a defensible place. Five mechanisms, each with a
machinery half and a preference half **[src]**:

| Mechanism | Machinery (library) | Decision (config) |
|---|---|---|
| **Discovery** | Window enumeration filtered to VS Code; `open-workspaces` parsing VS Code's own `globalStorage` state file; the last-focused socket pointer, whose path `root.scm:105` installs at boot | Nothing — but see below: *importing the library* is the only discovery mechanism there is |
| **Providers** | `terminal-provider` / `editor-provider` / `project-provider`: gather at come-to-rest, mint tokens, assign jump labels | Three alphabets each, panel labels, which panels exist at all |
| **Listings** | `blocks/part-list`, which **never queries** — its render hook reads the cell the provider filled, so rows and live labels cannot disagree | Panel titles, panel order, whether a listing is shown |
| **Activation** | `companion-installed?` probing the payload identity; `install-companion!` confirm-copy-reprobe | The key, the label, and pairing the row with `'hidden` so it retires itself |
| **Grove Leaf** | `focused-workspace-path` (VS Code only); `grove:live-leaf` (grove only) — neither knows the other | The **join**, the `and`-chain, and what to say on a miss |

The Grove Leaf row is the strongest evidence the line is drawn correctly: two
libraries that share no vocabulary compose in eight lines of ordinary Scheme, and
the composition is unmistakably preference.

### 1.1 Wiring a design could remove without reclaiming a preference

Four items are ceremony rather than choice **[inf]**:

1. **Three alphabets, one list, three times.** `'single-alphabet`,
   `'leader-alphabet` and `'second-alphabet` each receive `vscode-editor-keys`;
   the example's own comment calls passing one list three times "the ordinary
   case". The *pool* is preference; saying it thrice is not.
2. **Provider/listing pairing is restated by the user.** Every panel needs
   `X-provider` on the state's single `'provider` slot *and* `X-listing` inside a
   `panel`, and the contract that they agree is machinery — the listing is
   defined as reading its provider's snapshot. The user re-asserts a pairing the
   library already guarantees.
3. **The label is authored twice.** `'panel-label "Terminals"` goes to the
   provider; `(panel "Terminals" …)` says it again. One decision, two sites.
4. **Disjointness is the engine's rule, stated by hand.** Provider edges append
   into the state's own and resolve by first match, so a collision is a silent
   wrong jump; `jump-list-compose-providers` exists to raise instead. That the
   pools must stay disjoint over `single ∪ leader` is machinery. Which keys they
   contain is preference.

None of these is the ADR-0021 boundary moving. All four are the *authoring
surface* not yet expressing a decision compactly — precisely the gap ADR-0021's
Consequences predict ("expect one such gap per decision shape, and close it in
the DSL rather than re-admitting the decision").

---

## 2. Delivery channels

| Channel | Precedent | Who compiles | Skew handling | Crash radius | Covered by the two invariant checks? |
|---|---|---|---|---|---|
| App-bundled Scheme (`lib/modaliser/**.sld`) | 52 libraries | nobody — interpreted | impossible: mirror is exact (ADR-0019) | raises into config-failure degradation (ADR-0022) | **yes** |
| User-space Scheme (`config.scm`, `examples/`) | ADR-0021 | nobody | seed can strand *preference* only | load failure degrades | out of scope by design |
| In-process Swift, app-bundled (`*Library.swift`) | 16 registered in `SchemeEngine.init` | the app build | impossible — one binary | process death | no (Swift) |
| **In-process Swift, independently delivered** | none | third party | unsolved — see §4 | process death | **no** |
| Process-separated helper owned by Modaliser | none (herdr is foreign) | third party | negotiable | isolated | **no** |
| Companion inside the controlled app | ADR-0026/0027/0028 | the app build, installed on request | protocol version in the reply; mismatch ⇒ empty panel + log | isolated; miss ⇒ empty listing | **no** |

Two observations follow directly.

**The invariant checks are directory-scoped greps.** `check-decision-free.sh`
walks `find "$TARGET" -name '*.sld'` and `check-portable-surface.sh` runs
`grep -rnF` over the same `Sources/Modaliser/Scheme/lib/modaliser` **[src]**. Any
facility delivered by a new channel escapes *both* contracts by construction —
the TypeScript companion already does, and ADR-0026 says as much about ADR-0019's
mirror invariant. A facilities design that opens a channel owes a companion
answer to "what enforces the decision-free contract *there*", or an explicit
statement that it does not apply.

**The repo already ships a process-separated facility, and it works.** ADR-0026's
companion is the most instructive artifact in the codebase for this leaf, and it
was reached by rejecting both an accessibility reading and a stored-state read on
recorded grounds.

---

## 3. Interface shape: direct native vs. language-neutral semantic

### 3.1 The decisive property

Modaliser's current facility surface **passes procedures across the boundary**
**[src]**: `editor-cycler` returns a thunk and takes a `'focus` thunk;
`make-part-list-block` takes `'assigned-fn`, a thunk; providers *are* procedures;
`'hidden` takes a predicate; the outward seams are parameters holding runners.
This is not incidental — it is why ADR-0023's quarantine works at all, because a
seam holding `#f` is a capability the library does not have.

A language-neutral, data-only contract cannot express that. It must either make
callbacks a first-class protocol concept (LSP does: server→client requests) or
accept that the **composition layer stays in one host language** and the neutral
contract governs only the outward edge. That fork, more than any packaging
question, is what a facilities design has to settle.

### 3.2 The semantic surface the repo already has

ADR-0026/0027 specify a small facility protocol without calling it one:

| Element | How `parts` answers it |
|---|---|
| Queries / actions | Bounded method set — `parts`, `focus-terminal`, `focus-editor`. Deliberately **not** `executeCommand`: no caller can name a workbench command |
| Entity identity | (peer socket path, token). Tokens come from a never-reset counter; a socket path is never reused, so a stale target's message arrives nowhere rather than at the wrong part |
| Snapshots | One read per visit; rows and labels come from the same snapshot and cannot disagree |
| Availability / errors | Every miss — not installed, not activated, stale pointer, wedged host, version mismatch — ends as an **empty listing**, never wrong rows |
| Versioning | Protocol version in every reply; mismatch treated as unreachable |
| Actions vs. requests | Actions are notifications; only reads wait, on a 200 ms budget (`vscode.sld:1172`) |
| Subscriptions | Absent, and absence is the point — the door is open (`focused` is in the reply) but nothing pushes |

Compared against the two protocols that solve the same problem in the large, this
holds up:

| | Modaliser `parts` | [LSP 3.17](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/) | [Neovim API](https://neovim.io/doc/user/api.html) |
|---|---|---|---|
| Transport | NDJSON over AF_UNIX (ADR-0020) | JSON-RPC 2.0, `Content-Length` framing | MessagePack-RPC |
| Negotiation | version integer in reply | `initialize` capability exchange; clients ignore capabilities they don't understand rather than failing | `api_level` + `api_compatible`; signatures don't change after release except by additive extension |
| Cancellation | none — actions never wait | `$/cancelRequest`; server still responds | request ids |
| Degradation | empty listing | missing capability = feature absent | — |

The gap worth naming: **no cancellation and no capability negotiation**. A
version integer answers "can we talk"; it does not answer "does this peer support
subscriptions". If facilities generalise, LSP's shape — declare capabilities,
ignore what you don't understand — is the cheap upgrade, and it is what makes
scenario 4 (VS Code changes an operation) degrade rather than break **[inf]**.

### 3.3 Where a language adapter belongs

If the facility contract is **semantic**, the adapter is a thin per-language
client and closures never cross — which also means a future configuration
language inherits facilities for free. If the contract is **native**, the adapter
*is* the runtime, and every candidate language in `configuration-runtimes-k4`
pays for the whole surface again. This is the one place where the facilities
question and the language question are genuinely coupled, and it argues for
keeping the outward contract semantic even if nothing else changes.

---

## 4. Swift-specific constraints, and what is not solved

| Question | Evidence | Consequence |
|---|---|---|
| Is Swift's ABI stable? | Yes on Apple platforms since Swift 5 — [ABI Stability and More](https://www.swift.org/blog/abi-stability-and-more/) | This is *runtime* ABI. It is not a plugin ABI |
| Can modules built by different compilers interoperate? | Only with `-enable-library-evolution` + `.swiftinterface` — [Library Evolution in Swift](https://www.swift.org/blog/library-evolution/) | A plugin author and the app must both opt in, and the app's exported surface becomes resilient |
| Is there a Swift-native plugin interface? | No. The [Swift dynamic loading API thread](https://forums.swift.org/t/swift-dynamic-loading-api/39495) proposes one and describes today's state as C-shim `dlopen`/`dlsym`, failing when module ABIs are incompatible | Any plugin boundary is a C boundary, so Swift types, generics and error handling do not cross |
| Do SwiftPM plugins help? | No — [SwiftPM plugins](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/plugins/) are build-tool and command plugins running in a sandbox at build time | A name collision, not a mechanism. Worth stating so a design does not reach for it |
| Can a signed app load third-party code? | Only by adding [`com.apple.security.cs.disable-library-validation`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation), which forfeits the Gatekeeper check that library validation otherwise makes unnecessary | Modaliser is ad-hoc signed today (`release-build.sh:63`) **[src]**, so this cost is deferred, not avoided — it lands the day notarization does |
| Can a plugin be unloaded? | **[gap]** No primary source found. The dynamic-loading thread does not discuss `dlclose`; the [Emacs Dynamic Modules manual](https://www.gnu.org/software/emacs/manual/html_node/elisp/Dynamic-Modules.html) documents `module-load` and is silent on unloading and on crash containment | Assume load-once-per-process. Relaunch-only reload (ADR-0018) makes this cheap here, and that is a genuine local advantage |
| What thread does a facility run on? | In the app, all evaluation is main-thread (`SchemeEngine.swift:114` doc comment) **[src]**, inside the keyboard tap | A blocking plugin call is a frozen keyboard (ADR-0014). Any in-process contract needs the same bounded-or-inert shape the socket seams have |
| What does a crash cost? | In-process: the app. Out-of-process: [XPC services are launchd-managed, restarted on crash, each with its own sandbox](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html) *(archived documentation)* | The asymmetry is the whole argument, and it is the one [Zed made explicitly](https://zed.dev/blog/zed-decoded-extensions) when choosing Wasm so an extension could not crash the editor |

**One local constraint no external source covers.** An independently compiled
in-process plugin would have to speak LispKit's Swift API — `NativeLibrary`,
`Procedure`, `Expr` — since that is what `SchemeEngine.init` registers **[src]**.
Those are ordinary Swift types in a third-party package with no evolution
guarantee and no `.swiftinterface` contract. The plugin ABI question is therefore
*not* "is Swift's ABI stable" but "is LispKit's Swift surface stable", and the
answer is no. **[inf]**

---

## 5. Prior art, with the walk-away check

| System | Boundary | Walk-away: uninstall it, what stays legible? |
|---|---|---|
| [VS Code extension host](https://code.visualstudio.com/api/advanced-topics/extension-host) | separate process, no DOM access — stated as protecting stability *and* freedom to change the UI | `settings.json` and `keybindings.json` remain plain readable files; contributed commands vanish |
| [LSP](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/) | separate process, JSON-RPC, capability negotiation | The source file is untouched. Features go quiet; nothing is unreadable |
| [Neovim RPC](https://neovim.io/doc/user/api.html) | msgpack-rpc, any language, generated from C headers | `init.lua` stays a readable program; remote plugins simply do not answer |
| [Emacs dynamic modules](https://www.gnu.org/software/emacs/manual/html_node/elisp/Dynamic-Modules.html) | in-process C ABI | `.el` stays readable — but the failure mode is the whole editor, and the manual is silent on both unloading and containment |
| [Zed extensions](https://zed.dev/blog/zed-decoded-extensions) | Wasm sandbox, chosen so extensions cannot crash the editor and need no C compiler | Settings stay readable; grammars stop loading |
| [Wasm component model / WIT](https://component-model.bytecodealliance.org/design/wit.html) | language-agnostic IDL over a standardised ABI | n/a (a format, not a tool) — but it is the only mature answer to "in-process plugin without a native ABI" |
| **Modaliser's VS Code companion** (ADR-0026/0028) | separate process inside the controlled app | **The best answer in the table**: `config.scm` still loads, the screen still works, two panels are empty and one row reappears offering to install |

The companion's walk-away answer is strictly better than every in-process option
above, and it was not designed for that property — it falls out of "a miss is an
empty listing".

---

## 6. Three alternatives, and a provisional recommendation

| | **A — bundled only** | **B — semantic outward contract** | **C — in-process Swift plugins** |
|---|---|---|---|
| Facilities live | in the app | in the app, plus peers speaking one protocol | anywhere, loaded into the process |
| Contract | Scheme procedures | procedures inward; data + capabilities outward | LispKit Swift types |
| Third party can ship one | no | yes, in any language | yes, in Swift only |
| Crash radius | app | isolated | app |
| Invariant coverage | complete | needs a new rule per channel | none |
| New machinery | none | capability negotiation, one generalised transport | loading, signing, versioning, sandboxing |
| Precedent here | 52 libraries | ADR-0020/0026/0027/0028 | none |

**Provisional: B, with A as the default.** Generalise what ADR-0026 already
proved — a bounded method set, snapshot-scoped identity, actions as
notifications, timeout-to-empty, and a declared version — into *the* contract for
any facility that reaches outside the process, and add LSP-style capability
declaration so a facility can lose an operation without breaking a screen
(scenario 4). Keep in-process facilities as Scheme libraries, because passing
procedures is load-bearing (§3.1) and nothing about it is broken.

**C is not recommended now**, on five independent grounds, any one sufficient:
no Swift plugin ABI; LispKit's Swift surface is the real boundary and is
unstable; library validation must be disabled the day the app is notarized;
crash radius is the whole app inside a keyboard tap; and it escapes both
invariant checks.

**What would change it.** An external contributor wanting to ship a facility
Modaliser cannot bundle (ADR-0028 already names the analogous trigger for the
Marketplace question). A facility whose latency budget cannot absorb a round trip.
Swift gaining a supported plugin interface. Or the opposite discovery: that
[Wasm/WIT](https://component-model.bytecodealliance.org/design/wit.html) makes
in-process third-party code safe without an ABI, which is what Zed concluded —
that would reopen C in a form none of the five objections above touch.

---

## 7. Gaps, silences, and what design must settle

**Silences found.** No primary source states whether a Swift dylib can be safely
`dlclose`d; the one design thread on Swift dynamic loading does not raise it. The
Emacs manual's Dynamic Modules section documents loading and says nothing about
unloading or about a module crash taking the editor. Apple's modern XPC landing
page returned no body; the crash/restart statements above come from *archived*
documentation and should be re-verified before being leaned on.

**Not measured.** No plugin was built or loaded; no round trip was timed; no
signing configuration was tested. Every latency figure quoted is from the repo's
own recorded work, not from this task.

**For the human, not for research.** Whether third parties should be able to ship
facilities at all. Whether the companion pattern is acceptable as *the* answer for
in-app facilities, given it means one install per controlled app. Whether the
four ceremony items in §1.1 are worth DSL changes.

**For design (`configuration-design-k5`).** Which side of §3.1's fork to take —
procedures inward or data everywhere. What enforces the decision-free contract on
a channel the greps cannot see. Whether capability negotiation is added now or
deferred. Where subscriptions sit, given `parts` deliberately left the door open.

**Needs an experiment.** Whether an in-process facility can hold the keyboard
tap's budget without the socket's bounded-or-inert discipline. Whether a
capability-negotiating handshake costs anything measurable at come-to-rest.

## Sources

All consulted 2026-09-10.

- [ABI Stability and More — Swift.org](https://www.swift.org/blog/abi-stability-and-more/)
- [Library Evolution in Swift — Swift.org](https://www.swift.org/blog/library-evolution/)
- [Swift dynamic loading API — Swift Forums](https://forums.swift.org/t/swift-dynamic-loading-api/39495)
- [SwiftPM Plugins — docs.swift.org](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/plugins/)
- [Disable Library Validation Entitlement — Apple](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation)
- [Creating XPC Services — Apple (archived)](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html)
- [Extension Host — VS Code API](https://code.visualstudio.com/api/advanced-topics/extension-host)
- [Language Server Protocol 3.17](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/)
- [Nvim API — neovim.io](https://neovim.io/doc/user/api.html)
- [Dynamic Modules — GNU Emacs Lisp Reference Manual](https://www.gnu.org/software/emacs/manual/html_node/elisp/Dynamic-Modules.html)
- [Life of a Zed Extension: Rust, WIT, Wasm — Zed](https://zed.dev/blog/zed-decoded-extensions)
- [WIT Reference — WebAssembly Component Model](https://component-model.bytecodealliance.org/design/wit.html)

In-repo: ADR-0011, ADR-0014, ADR-0018, ADR-0019, ADR-0020, ADR-0021, ADR-0022,
ADR-0023, ADR-0026, ADR-0027, ADR-0028; `docs/specs/vscode-window-parts.md`;
`Sources/Modaliser/Scheme/examples/vscode.scm`;
`Sources/Modaliser/Scheme/lib/modaliser/apps/vscode.sld`;
`Sources/Modaliser/Scheme/lib/modaliser/blocks/part-list.sld`;
`Sources/Modaliser/Scheme/root.scm`; `Sources/Modaliser/SchemeEngine.swift`;
`scripts/check-decision-free.sh`; `scripts/check-portable-surface.sh`;
`scripts/release-build.sh`; `CONTEXT.md`.
