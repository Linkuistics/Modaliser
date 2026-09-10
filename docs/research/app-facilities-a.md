# Separating app-control facilities from user composition — survey (a)

Exploratory research for `configuration-exploration`. External sources consulted
**2026-09-10**, paraphrased unless the wording carries the claim. The inspected
revision is **`b5886f81`**, this grove's parent.

A survey, not a decision. ADR-0021 is the baseline being extended, not a proposal
being made. Nothing here authorises implementation, a plugin format, or an
install.

**Corrected in place 2026-09-10** by `configuration-design-k5`, against the
primary sources cited below. Six claims were overstated: the Swift-plugin option
assumed every native plugin must speak LispKit's own Swift types (§4.1 is new);
absence of a Swift plugin *interface* was read as absence of a *bootstrap*
mechanism (§4); library validation was treated as unconditional rather than
signing-dependent (§4); evaluation was placed "inside the keyboard tap" when it
is dispatched to the main queue (§4); Neovim's request ids were read as a
cancellation protocol (§3.2); and four claims — "skew impossible", "invariant
coverage complete", "inherits facilities for free", WIT as "the only mature
answer" — asserted more than their evidence carries. The recommendation (§6)
survives, on **three** grounds rather than five, and §4.1 states what a Swift
facility module would still have to settle.

| Mark | Meaning |
|---|---|
| **[src]** | Read out of this repository at the revision above; file and line given. |
| **[doc]** | A dated primary external source, linked at the claim. |
| **[inf]** | Derived from **[src]** + **[doc]**. An inference, not a verified fact — no observation supports it. |
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
| App-bundled Scheme (`lib/modaliser/**.sld`) | 52 libraries | nobody — interpreted | structurally excluded: `build-app.sh` fails the build unless the bundled tree matches the source tree exactly (ADR-0019) | raises into config-failure degradation (ADR-0022) | **yes** |
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
| Cancellation | none — actions never wait | `$/cancelRequest`; server still responds | **[gap]** none found. Msgids correlate a reply with its request; `runtime/doc/api.txt`'s only occurrence of *cancel* is a progress-message concept, not an RPC verb |
| Degradation | empty listing | missing capability = feature absent | — |

The gap worth naming: **no cancellation and no capability negotiation**. A
version integer answers "can we talk"; it does not answer "does this peer support
subscriptions". If facilities generalise, LSP's shape — declare capabilities,
ignore what you don't understand — is the cheap upgrade, and it is what makes
scenario 4 (VS Code changes an operation) degrade rather than break **[inf]**.

### 3.3 Where a language adapter belongs

If the facility contract is **semantic**, the adapter is a thin per-language
client and closures never cross — so a future configuration language reaches
every existing facility through **one adapter**, rather than re-implementing each
facility. That is a large saving, not a free one **[inf]**: the adapter still owes
marshalling for every operation *type* the contract admits, a mapping from
transport and peer errors into the language's own error model, and — the day
subscriptions are added (§3.2) — an inbound-callback story. The cost is
per-language and roughly constant in the number of facilities; the native
alternative is per-language **and** per-facility. If the contract is **native**,
the adapter *is* the runtime, and every candidate language in
`configuration-runtimes-k4` pays for the whole surface again. This is the one place where the facilities
question and the language question are genuinely coupled, and it argues for
keeping the outward contract semantic even if nothing else changes.

---

## 4. Swift-specific constraints, and what is not solved

| Question | Evidence | Consequence |
|---|---|---|
| Is Swift's ABI stable? | Yes on Apple platforms since Swift 5 — [ABI Stability and More](https://www.swift.org/blog/abi-stability-and-more/) | This is *runtime* ABI. It is not a plugin ABI |
| Can modules built by different compilers interoperate? | Only with `-enable-library-evolution` + `.swiftinterface` — [Library Evolution in Swift](https://www.swift.org/blog/library-evolution/), which **also** directs that frameworks always built and shipped alongside their clients — SwiftPM packages, or binary frameworks internal to an app — should *not* enable it, and notes that turning it on is itself a binary-incompatible change | The requirement is **conditional on separate distribution**, not on being a facility. A facility module compiled with the app needs none of it. Only a separately built-and-updated one does, and then both sides opt in and the app's exported surface becomes resilient — a real cost, correctly scoped to that one delivery shape |
| Is there a Swift-native plugin *interface*? | No. The [Swift dynamic loading API thread](https://forums.swift.org/t/swift-dynamic-loading-api/39495) proposes one and describes today's state as C-shim `dlopen`/`dlsym`, failing when module ABIs are incompatible | No Swift-declared plugin protocol exists. That bounds the **interface ABI** — what may cross — and says nothing about the **bootstrap**, which is the next row |
| Is there a documented *bootstrap* mechanism? | Yes, and an old one. Apple's [Loading Bundles](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/LoadingCode/Tasks/LoadingBundles.html) documents `NSBundle` `bundleWithPath:` → `load` → `principalClass` → instantiate, plus `builtInPlugInsPath` for discovery and `CFBundleGetFunctionPointerForName` for non-Cocoa bundles. It does not discuss unloading | Discovery and entry are solved, and they bound only the **entry point**: it must be Objective-C- or C-visible. They do **not** bound what that entry hands back — §4.1 separates the three layers |
| Do SwiftPM plugins help? | No — [SwiftPM plugins](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/plugins/) are build-tool and command plugins running in a sandbox at build time | A name collision, not a mechanism. Worth stating so a design does not reach for it |
| Can a signed app load a library? | **Depends whose.** Apple's [Code Signing Tasks](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html) permits a program to link against libraries sharing the main executable's team identifier, and against Apple system libraries; it denies everything else. [`com.apple.security.cs.disable-library-validation`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation) is required only to load code signed by a **different** team | The cost is **per plugin origin, not per plugin design**. A facility module bundled in the app, or shipped later by the same Team ID, stays inside library validation. Only arbitrary third-party binaries force the entitlement, and only once Modaliser stops being ad-hoc signed (`release-build.sh:63`) **[src]**. The earlier reading — that notarisation inevitably costs library validation — held only for that third-party case |
| Can a plugin be unloaded? | **[gap]** No primary source found. The dynamic-loading thread does not discuss `dlclose`; the [Emacs Dynamic Modules manual](https://www.gnu.org/software/emacs/manual/html_node/elisp/Dynamic-Modules.html) documents `module-load` and is silent on unloading and on crash containment | Assume load-once-per-process. Relaunch-only reload (ADR-0018) makes this cheap here, and that is a genuine local advantage |
| What thread does a facility run on? | The **main queue** — not the tap. The tap services its own run loop on a dedicated high-priority thread (`KeyboardCapture.swift:88-96`); `fireHotkeyHandler` installs a capture buffer and *then* does `DispatchQueue.main.async { context.withEvalLockNonBlocking { … } }` (`KeyboardLibrary.swift:183-189`), as does `registerAllKeysFunction` (`:310-311`) **[src]** | A blocking facility call blocks the **main thread** — AppKit, menus, timers, the overlay — and delays replay of the buffered keystrokes. It does **not** stall the tap, which keeps buffering; the failure is latency and a wedged UI, not input dropped at the tap. Whether input is ultimately lost is **[gap]** (`configuration-runtimes-a.md` §2.3 reaches the same reading). The bounded-or-inert shape the socket seams have is still the right discipline (ADR-0014) |
| What does a crash cost? | In-process: the app. Out-of-process: [XPC services are launchd-managed, restarted on crash, each with its own sandbox](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html) *(archived documentation)* | The asymmetry is the whole argument, and it is the one [Zed made explicitly](https://zed.dev/blog/zed-decoded-extensions) when choosing Wasm so an extension could not crash the editor |

### 4.1 A Swift facility module with an app-owned interface

**The LispKit constraint is a property of one design, not of Swift.** Today's 16
native libraries are `NativeLibrary` subclasses registered in `SchemeEngine.init`
**[src]**, so *extending that registration mechanism* to third-party code would
indeed make LispKit's `NativeLibrary`/`Procedure`/`Expr` the plugin ABI — ordinary
Swift types in a package pinned to `branch: "master"`, with no evolution guarantee
and no `.swiftinterface`. That is a decisive objection **to that one shape**, and
the previous draft of this survey generalised it to every Swift plugin. It does
not generalise: nothing requires a facility to be a *Scheme* library.

The alternative is an **app-owned semantic interface**: Modaliser declares what a
facility is — entities, queries, actions, availability, errors — in its own
vocabulary, and a separate **adapter** maps that interface onto whichever
configuration language is resident. This is the in-process twin of §3.3's
outward contract, and it decouples the two questions that the LispKit reading
fused.

**Three layers, and conflating them is what produced the original overstatement.**
*Bootstrap* is how the app finds and enters plugin code; *interface* is the type
the entry point hands back and the operations declared on it; *payload types* are
the concrete values each operation exchanges. The documented bootstrap
(`principalClass`, or a C function pointer) constrains only the first: the entry
must be Objective-C- or C-visible. Nothing about that forces the interface or the
payload types into the Objective-C/C subset. An `@objc` entry point can perfectly
well return an object conforming to a **Swift protocol declared in a shared SDK
module** that app and plugin both link, after which the operations and their
payload types are ordinary Swift — generics, `Result`, typed `throws` and all.
That shared-SDK candidate is the one worth designing towards, and its costs are
real but nameable rather than disqualifying:

- **It becomes the versioned artifact.** The SDK, not the app, is what a plugin
  builds against, so it needs a declared version, a compatibility policy, and a
  distribution channel of its own.
- **It is precisely the case library evolution exists for.** Apple's guidance
  says to enable it only for frameworks built and updated separately from their
  clients **[doc]** — which is exactly a plugin SDK, and not the app's own
  internal modules. Enabling it is itself binary-incompatible, so the decision
  comes at the start.
- **The compiler checks the interface, not the version skew.** Both sides
  compiling against one SDK version gives real type checking — a genuine
  advantage over an `@objc`/C vtable. What no compiler checks is a plugin built
  against SDK v1 loaded into an app carrying v2; that is what library evolution
  plus a declared version negotiation is for, and it is an ongoing obligation.
- **Swift's runtime ABI stability is a precondition, not the answer.** Stable
  since Swift 5 on Apple platforms **[doc]**, it makes the language runtime side
  work; the *module* interface side is the evolution question above.

Four delivery shapes fall out of that, and they are not equally hard:

| Shape | Bootstrap | Interface ABI | Library evolution | Library validation | What is unproven |
|---|---|---|---|---|---|
| **Source module built with the app** | none — ordinary linking | none — one compilation unit | not needed, and Apple says not to enable it **[doc]** | inside the app's own signature | nothing structural; the cost is that a facility ships on the app's release train |
| **Binary framework, same Team ID** | `NSBundle`/`principalClass` **[doc]** | `@objc`/C **entry point**; the interface behind it may be Swift, via a shared SDK module both sides link | needed **on the shared SDK**, which is separately built and updated **[doc]** | allowed — same team identifier **[doc]** | how the shared SDK is versioned, distributed and kept compatible; whether its Swift surface survives evolution mode without losing the typing that motivated it **[gap]** |
| **Binary framework, third-party signature** | same | same | same | **denied** unless the entitlement is added **[doc]** | trust, versioning, and everything in the row above |
| **Out-of-process peer** | socket, ADR-0020 | data, versioned in the reply | n/a | n/a | nothing — ADR-0026 already ships one |

Three consequences a design must carry.

**A versioned native boundary is unavoidable and is not free.** Whatever a
binary plugin is built against is a frozen surface the moment it ships, so the
same negotiation the socket contract already has — declare a version, declare
capabilities, degrade rather than fail (§3.2) — has to exist here too. A shared
Swift SDK makes the *interface* compiler-checked when both sides build against
one version, which an `@objc` vtable would not; **version skew across releases is
what remains unchecked**, and that is what library evolution plus a declared
version answers. Sharing one *semantic* interface across the native and the
socket boundary is what makes the negotiation tractable; maintaining two
different ones is what makes it expensive.

**Helpers are the hidden bulk.** Whatever crosses, something must turn it into
the resident language's values, and back. That is the same adapter cost §3.3
prices for the outward contract, and building the facility *with* the app removes
the ABI question, not the marshalling one.

**Crash radius does not improve.** Every in-process shape above puts a facility's
faults in Modaliser's address space and on its main queue. That is the argument
the companion answers and no in-process shape can (§5).

**What remains unproven for a Swift implementation. [gap]** No such module was
built, loaded, or signed here. Specifically: what a shared plugin SDK costs to
version, distribute and keep binary-compatible across app releases; whether its
Swift surface survives library-evolution mode with the typing that motivated it
intact; and whether a Swift dylib can be safely `dlclose`d (no primary source
found — §7). None of these is a demonstrated impossibility; all are unpriced.

---

## 5. Prior art, with the walk-away check

| System | Boundary | Walk-away: uninstall it, what stays legible? |
|---|---|---|
| [VS Code extension host](https://code.visualstudio.com/api/advanced-topics/extension-host) | separate process, no DOM access — stated as protecting stability *and* freedom to change the UI | `settings.json` and `keybindings.json` remain plain readable files; contributed commands vanish |
| [LSP](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/) | separate process, JSON-RPC, capability negotiation | The source file is untouched. Features go quiet; nothing is unreadable |
| [Neovim RPC](https://neovim.io/doc/user/api.html) | msgpack-rpc, any language, generated from C headers | `init.lua` stays a readable program; remote plugins simply do not answer |
| [Emacs dynamic modules](https://www.gnu.org/software/emacs/manual/html_node/elisp/Dynamic-Modules.html) | in-process C ABI | `.el` stays readable — but the failure mode is the whole editor, and the manual is silent on both unloading and containment |
| [Zed extensions](https://zed.dev/blog/zed-decoded-extensions) | Wasm sandbox, chosen so extensions cannot crash the editor and need no C compiler | Settings stay readable; grammars stop loading |
| [Wasm component model / WIT](https://component-model.bytecodealliance.org/design/wit.html) | language-agnostic IDL over a standardised ABI | n/a (a format, not a tool) — the most mature answer *found in this survey* to "in-process plugin without a native ABI". No systematic search for alternatives was made **[gap]** |
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
| Invariant coverage | complete *for `.sld` files under `lib/modaliser`* — which is the whole of what both greps scope to | needs a new rule per channel | none from the two greps; `_ENV`-style scoping or an app-owned interface would need its own mechanism |
| New machinery | none | capability negotiation, one generalised transport | loading, signing, versioning, sandboxing |
| Precedent here | 52 libraries | ADR-0020/0026/0027/0028 | none |

**Provisional: B, with A as the default.** Generalise what ADR-0026 already
proved — a bounded method set, snapshot-scoped identity, actions as
notifications, timeout-to-empty, and a declared version — into *the* contract for
any facility that reaches outside the process, and add LSP-style capability
declaration so a facility can lose an operation without breaking a screen
(scenario 4). Keep in-process facilities as Scheme libraries, because passing
procedures is load-bearing (§3.1) and nothing about it is broken.

**C is not recommended now** — but on **three** grounds rather than five, because
the source checks in §4 dissolved two of them. What survives, any one sufficient:

1. **Crash radius is the whole app**, and a fault lands on the main queue that
   AppKit, the overlay and the buffered-keystroke replay all share (§4). The
   companion pattern already avoids this and cost nothing extra to get.
2. **A second versioned boundary has to be designed and maintained** (§4.1). A
   shared Swift SDK gets the *interface* type-checked, which an `@objc` vtable
   would not — but nothing checks a plugin built against one SDK version running
   against another, so it needs library evolution, a declared version and a
   distribution channel. The socket contract already carries one such
   negotiation; this is a second one to keep honest.
3. **It escapes both invariant checks**, which are directory-scoped greps over
   `.sld` files (§2), and nothing yet proposes what replaces them there.

**Two earlier grounds do not survive.** *"LispKit's Swift surface is the real
boundary"* is true only for a plugin registered as a Scheme library; an app-owned
semantic interface — plausibly a shared Swift SDK behind an `@objc` entry point —
with a per-language adapter removes it (§4.1), at the cost of ground 2. And *"library validation must be disabled the day the app is
notarized"* is false as stated: same-Team-ID and Apple system libraries are
permitted **[doc]**, so the entitlement is forced only by arbitrary third-party
binaries (§4). A **bundled** Swift facility module — the first row of §4.1's
table — clears both, which makes it the honest floor of option C rather than a
straw man.

**What would change it.** An external contributor wanting to ship a facility
Modaliser cannot bundle (ADR-0028 already names the analogous trigger for the
Marketplace question). A facility whose latency budget cannot absorb a round trip.
Swift gaining a supported plugin interface. A decision to move the *language*
(`configuration-runtimes-a.md`), which makes an app-owned semantic interface
worth building for its own sake and drops ground 2's marginal cost to near zero.
Or the opposite discovery: that
[Wasm/WIT](https://component-model.bytecodealliance.org/design/wit.html) makes
in-process third-party code safe without an ABI, which is what Zed concluded —
that would reopen C in a form none of the three objections above touch.

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
