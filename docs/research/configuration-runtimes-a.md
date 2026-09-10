# Configuration languages and the runtime boundary — survey (a)

Exploratory research for `configuration-exploration`. External sources consulted
**2026-09-10**, paraphrased unless the wording carries the claim. The inspected
revision is **`a97a1bf2`**, this grove's parent.

A survey, not a decision. Nothing here authorises a language change, a runtime
replacement, a dependency, or a build task. No runtime was installed, embedded,
started, benchmarked, or packaged; every performance number is either quoted
from a primary source with its date, or marked unmeasured.

| Mark | Meaning |
|---|---|
| **[src]** | Read out of this repository at the revision above; file and line given. |
| **[doc]** | A dated primary external source, linked at the claim. |
| **[inf]** | Inferred from **[src]** + **[doc]**. Inference, not verified. |
| **[gap]** | Not established: no primary source found, or it needs an experiment. |

**Corrected in place 2026-09-10** by `configuration-design-k5`, and recorded here
by `configuration-design-k7` (the note was omitted when the corrections landed —
this header previously named only the inspected revision above, so post-survey
judgment sat inside the survey without provenance). Two corrections: §3's
declarative-front-end option was rewritten from a single "named operations only"
shape into a **spectrum** whose real variable is how much interpreter the data
format carries, with the matching row added to §6.2's Grove Leaf table; and §8's
SBCL summary said a *third* tracing collector where Swift's ARC is reference
counting, not tracing, so the count is **two**. Both are marked **[inf]** where
they infer. Findings and recommendation are unchanged.

---

## 0. Three questions, deliberately not merged

1. **Authoring surface** — what the user's `config.scm` is written in.
2. **Runtime location** — a startup-only front end, a resident configuration
   runtime, or a full replacement of the Scheme runtime.
3. **Native boundary ownership** — what shape the app's capabilities take when
   they cross into the configuration language.

Axis 3 is a **design variable, not a constant**. The current
`NativeLibrary`/`Expr` bridge (16 Swift libraries registered in
`SchemeEngine.init` **[src]**) is one possible boundary; a new semantic Swift
interface with per-language adapters is a live candidate and is not evaluated
here as though the existing bridge were fixed.

The axes are near-independent: a TypeScript authoring surface does not require a
JavaScript runtime to own the state machine, and a full Scheme replacement does
not require the user's file to stop being s-expressions.

---

## 1. The baseline, measured

### 1.1 What is actually there

| Quantity | Value **[src]** |
|---|---|
| Swift | 7 457 lines, 16 `*Library.swift` native libraries |
| Scheme library tree | 52 `.sld`, 20 250 lines |
| Host Scheme (`root.scm`, `ui/`, examples, default config) | 9 `.scm`, 3 807 lines |
| Renderer assets | 12 `.js`, 11 `.css` |
| Imports in `.sld` files | 529 `(modaliser …)`, 91 `(scheme …)`, 6 `(srfi …)`, **0 `(lispkit …)`** |
| LispKit built-in libraries imported by the host | 8 — Base, List, HashTable, String, Port, System, Math, Bytevector |

The zero is real, not a grep artifact: the same pattern shape finds
`(scheme base)` 64 times in the same trees. It is also stronger than the
portability contract requires — `check-portable-surface.sh` scopes to
`lib/modaliser`, yet `root.scm` and `ui/*.scm` name no host library either. They
do not need to: they are flat-`include`d into an environment where the host has
already imported LispKit's standard libraries, so **the LispKit dependency is
injected by the host and named nowhere in Scheme**.

### 1.2 The language surface the tree actually uses

This is the measurement that decides how portable 24 000 lines of Scheme are,
and it is not what a reader would guess:

| Form | Occurrences **[src]** | Reading |
|---|---|---|
| `define` | 1 536 | — |
| `(assoc` / `(assq` | 308 / 27 | alists are the universal record type |
| `(car` / `(cdr` | 474 / 684 | ditto |
| `make-parameter` / `parameterize` | 20 / 4 | dynamic parameters carry the ADR-0023 seams |
| `guard` | 19 | exceptions are used, deliberately |
| `hash-table*` | 14 | secondary |
| `define-record-type` | 3 | — |
| **`define-syntax` / `syntax-rules`** | **3 / 3** | — |
| `dynamic-wind` | **0** | — |
| `call-with-current-continuation` | **0** | — |
| `with-exception-handler` | 0 | `guard` only |

Three macros exist in the whole tree: `layout-block`
(`window-actions.sld:107`), `key` (`dsl.sld:91`), and `λ` — an alias for
`lambda` (`dsl.sld:104`) **[src]**.

Two consequences, and they point in opposite directions from the usual argument.

**"We need Scheme's macros" is not supported by the evidence.** The user-facing
DSL's expressive power comes from higher-order procedures and quoted symbols,
not from syntactic abstraction. `key` is the single syntactic form that carries
weight.

**The tree uses none of Scheme's hard-to-port control features.** No
continuations, no `dynamic-wind`. The surface in use — procedures, closures,
association lists, hash tables, dynamic parameters, `guard`, and a module
system — exists in **all four** candidate languages. That is what makes full
replacement arguable at all, and it is a consequence of the portability contract
having been enforced for other reasons.

### 1.3 Three baseline defects that are runtime properties, not code smells

These are the axes that actually discriminate between candidates. A generic
feature matrix finds none of them.

**(a) `string-ref` is Θ(n), and it cost 27 seconds.** `instrument.sld`'s header
records the reading: a leader press with herdr focused stalled for ~27 s, and a
`sample` profile of the installed app put **97 % of that inside LispKit's
`string-ref`** under `fireHotkeyHandler`, because LispKit backs Scheme strings
with `NSMutableString` and `string-ref` bridges the whole string per call
**[src]**. The tree's response is visible in the code: `apps/vscode.sld:832`
scans **vectors, never strings**, and 24 `string-ref` sites remain as candidates
**[src]**. This is the only hard local performance datum in the workstream, and
it is a property of the *implementation*, not of Scheme.

**(b) The runtime cannot protect its own evaluation.** ADR-0022 exists entirely
because of this: LispKit implements `raise` in Scheme, so `guard` sees only
conditions a Scheme program raised deliberately, while the three ways a config
actually fails — read error, type error, unbound variable — are thrown out of
the VM as host errors and unwind past every Scheme handler; each was *measured*
escaping a `guard`. And no native primitive can wrap the load, because
`evaluator.execute` asserts top level, so nested evaluation is a precondition
failure **[src]**. The result is that config-failure recovery is sequenced by
the host as two sequential top-level evaluations. ADR-0022 names its own
reopening condition: a LispKit API for re-entrant evaluation with clean unwind.

**(c) Immutable pairs and a thin standard library.** LispKit's own README lists
immutable lists as a deliberate R7RS incompatibility — "Mutable cons-cells are
supported in a way similar to Racket" **[doc]**. The tree's cost is visible: no
`set-car!`/`set-cdr!` anywhere, so state is rebuilt as fresh alists (`fsm.sld:40`,
`terminal.sld:328`, `theming.sld:246` **[src]**); no `list-sort`, so
`apps/vscode.sld:605` and `muxes/herdr.sld:1831` hand-roll stable insertion sorts
**[src]**; no SRFI 13 in the bundle, so `util.sld:18` carries local string
helpers **[src]**. Four further sites document LispKit snapshotting the *value*
of mutable top-level imports at compile time, which shapes real code
(`fsm.sld:1664`, `1703`, `1747`, `overlay.scm:250` **[src]**).

### 1.4 What the baseline gets right, and what it costs to keep

LispKit is purpose-built for precisely this job — "a framework for building
Lisp-based extension and scripting languages for macOS and iOS applications"
**[doc]** — and it supports tail calls and continuations, the R7RS library
system, and SRFI-18 threading (which the tree uses **0** times **[src]**).
Its hosting cost is the lowest available: a Swift package, no separate runtime
artifact, no boot files, no JIT, no signal handlers, no second garbage collector.

Against that: `Package.swift` pins it to **`branch: "master"`**, not a version,
and it brings 15 transitive dependencies including OAuth2, KeychainAccess,
SQLiteExpress, ZIPFoundation, SWCompression and CBORCoding **[src]**. An
unpinned upstream is the baseline's own supply-chain exposure, and it is
independent of every question in this leaf.

---

## 2. The boundary as it actually is

### 2.1 Procedures are pervasive inside, rare at the edge

| Where | Count **[src]** |
|---|---|
| Procedures in `lib/modaliser` | ~1 400 (1 096 `(define (`, 303 `(lambda (`) |
| Native libraries that accept a Scheme procedure | **5** — Http, Keyboard, Lifecycle, Shell, WebView (7 sites) |
| Places Swift **retains** a Scheme procedure across host calls | **2** registries — `LifecycleLibrary.menuActionHandlers` (`:16`), `KeyboardHandlerRegistry._hotkeyHandlers` (`:43`) |

This asymmetry is the most useful structural fact in the leaf, and it cuts
cleanly across axes 2 and 3:

- A **native-boundary redesign** does not have to solve procedure passing. Seven
  sites and two retained registries is a small, enumerable surface. The
  coordinator's semantic-interface-plus-adapters candidate is not blocked by the
  callback story.
- A **language replacement** must preserve first-class procedures *pervasively*,
  because 303 anonymous closures and the entire provider/thunk/predicate idiom
  live inside the Scheme tier and never cross into Swift.

### 2.2 Two boundary shapes are already in production

| Boundary | Shape | Evidence |
|---|---|---|
| Scheme ↔ Swift | **synchronous, procedure-passing**, same process, one evaluator behind a recursive-lock fence | `SchemeEngine.swift:73-125` **[src]** |
| Scheme ↔ JavaScript | **asynchronous, data-push plus callback-message**, no procedures cross | `WebViewLibrary.swift:90-98`, `:101-117` **[src]** |

The second is worth dwelling on. `webview-eval` is fire-and-forget with the
comment "Synchronous for now — `evaluateJavaScript` is async but we need to
return a result… callers that need results should use `webview-on-message`
instead" **[src]**. The overlay and chooser are driven entirely that way — the
Display-PostScript pattern the repo already documents. So the app **already runs
a second language across an async, procedure-free, out-of-process boundary, and
it works** — because the protocol is data plus a callback channel, not shared
closures. Any process-separated configuration runtime would inherit that shape,
and the renderer is the existence proof that the shape is liveable for
presentation. It is *not* evidence that the same shape suits the composition
tier, which is where the closures are.

### 2.3 The host owns the event loop, and input is already decoupled

| Property | Detail **[src]** |
|---|---|
| Event tap | Own thread, own run loop (`KeyboardCapture.swift:92-96`); re-enables itself on `tapDisabledByTimeout` (`:145-148`) |
| Evaluation | `fireHotkeyHandler` installs a capture buffer, then `DispatchQueue.main.async { context.withEvalLockNonBlocking { … } }` (`KeyboardLibrary.swift:183-189`) |
| Stated intent | "Even if Scheme spends seconds shelling out to AppleScript probes, the tap (on its own thread) keeps buffering keystrokes meanwhile" (`KeyboardLibrary.swift:186-187`) |
| Evaluator | Single-threaded, serialized by `ModaliserContext.evalLock`; `gcDelay: 5.0`, `limitStack: 10 000 000` (`SchemeEngine.swift:74`, `:87-89`) |

**Evaluation is asynchronous with respect to the tap.** A slow runtime therefore
costs *overlay latency* — the visible delay before which-key appears, and the
delay before buffered keystrokes are replayed. The buffer is installed before
dispatch specifically to mitigate keystroke loss, and the comment above states
that intent, but **no test here establishes that no keystroke is lost** — the
tap's own `tapDisabledByTimeout` path exists, and the mitigation is unproved
**[gap]**. What the source does establish is that evaluation is not on the tap
thread, so throughput governs perceived responsiveness rather than a hard
real-time deadline.

The contract a candidate must satisfy is therefore modest and precise: **be a
passive, re-entrant-safe evaluator that the host calls from the main queue, and
never demand ownership of the run loop.** Runtimes that want to *be* the event
loop (a Node-style runtime, an SBCL image with its own signal handlers) fight
this; runtimes designed for embedding do not.

---

## 3. The three execution shapes, and what each cannot do

| Shape | Definition | The thing it cannot do |
|---|---|---|
| **Startup-only front end** | The user's file is read once at boot and produces a value the resident LispKit runtime consumes. | It must *emit* something. Serialised data cannot carry the 303 closures, the `'hidden` predicates, the provider thunks, or the `'assigned-fn` hooks. |
| **Resident configuration runtime** | A second runtime lives for the app's lifetime beside LispKit; user code runs in it; the tiers talk over a defined protocol. | Two GCs, two error models, and a protocol that must carry per-visit live data (`configuration-exploration-context.md`, Live data). |
| **Full replacement** | The candidate replaces LispKit; the 24 000-line tree is ported or rewritten. | One-shot cost proportional to §1.2, and every `-native` seam and ADR-0023 quarantine re-established in the new host. |

The front-end shape deserves the sharpest treatment because it sounds cheapest
and is the most often mis-specified. Given the closure evidence, it has exactly
three honest realisations:

1. **Transpiler.** The front end compiles to Scheme source, so `lambda` becomes
   `lambda` and closures survive. This is compilation, not serialisation, and its
   real cost is diagnostics: an error raised at runtime points into generated
   Scheme, and ADR-0022 shows the host cannot even catch it in-language today.
2. **Declarative surface.** The config becomes data rather than a program in the
   resident language. This is the shape that makes multi-language plausible, and
   it is a **spectrum, not a single option**. At one end, data referencing
   library-exported operations by name and nothing else: no user closures, and
   the Grove Leaf scenario fails unless the library ships that join, because the
   `and`-chain is user-authored behaviour. At the other end, a data
   representation that carries its own sequencing, conditionals, bindings and
   expression forms — which *can* express the join, at the price of being an
   additional language and interpreter to design, document and produce
   diagnostics for. Neither end is "declarative composition is impossible"; the
   real variable is how much interpreter the format contains, and every increment
   of it is language-design work that the resident-runtime shapes get for free
   **[inf]**.
3. **Hybrid.** Declarative for grouping/keys/layout, escape hatch for behaviour.
   The escape hatch's language is then the resident language, so the user learns
   two.

**A toolchain-dependent front end changes the install story.** Any shape needing
`tsc`, `raco`, or a Lisp at *authoring* time makes a compiler a user-facing
prerequisite for a Homebrew-cask app whose users are not necessarily developers
— unless the toolchain ships inside the `.app`, which is embedding by another
name. This is a distribution consequence, not a technical one, and it is easy to
miss when comparing languages on their merits **[inf]**.

---

## 4. The five candidates

### 4.1 LispKit / Scheme (baseline)

Covered in §1. Hosting cost effectively zero; the three defects of §1.3 are the
case against; two of the three are *implementation* defects that could be fixed
upstream or worked around without changing language, and ADR-0022 already states
the API change that would close (b).

**Walk-away check:** the strongest in the set, and engineered rather than lucky.
`config.scm` is s-expressions readable as data; the 52-library tree names 91
`(scheme …)` and 6 `(srfi …)` imports and **no** host library, so another R7RS
host could load it modulo the quirks §1.3(c) already documents in comments
**[src]**.

### 4.2 Racket

**Embedding.** `racket_boot()` with a `racket_boot_arguments_t`; on macOS you
link **the Racket framework** (`libracketcs.a` on other Unix). Three boot files
— `petite.boot`, `scheme.boot`, `racket.boot` — are required, by path or embedded
as binary data via `boot*_data`/`boot*_len`; `raco ctool --c-mods` generates C
encapsulating compiled modules, so nothing need be located at runtime **[doc]**.

**Retaining values across calls — a documented mechanism, not a prohibition.**
The embedding page warns that Racket values may move or be collected across any
`racket_…` call, so a bare reference must not be held **[doc]**. That is not the
whole story: the values-and-types page documents `Slock_object` /
`Sunlock_object`, which pin an object against collection and relocation, and
recommends the idiom for several values — allocate and lock **one vector** with a
slot per otherwise-unlocked object — while cautioning that the collector is not
designed for large numbers of locked objects **[doc]**. Read against §2.1 the fit
is good: the surface retaining values across host calls is two registries, so one
locked handle vector each is the documented shape, not an exotic workaround
**[inf]**.

**Front-end story.** `#lang` lets an implementer set both the reader and the
expander starting point, which macros alone cannot do — a macro cannot restrict
the syntax available in its context; `#lang s-exp` and `syntax/module-reader` are
the tools **[doc]**. Racket is **not** the only candidate permitting notation
design: Common Lisp's reader macros and readtables do it too, and a host
embedding any candidate can always parse a notation itself. Racket's distinctive
property is narrower and worth stating precisely — the reader *and* the expander
are selected **per file, by its first line**, so one config file's notation and
its available bindings are chosen together and scoped to that file, where a CL
readtable change is a mutation of a shared reader **[inf]**.

**Porting the existing tree.** Racket's R7RS-small implementation is a
**package** — `#lang r7rs` — with all R7RS libraries present. Documented
caveats: `define-library` is restricted for compatibility with Racket's module
system; `(scheme base)` lacks `include-ci`; `exit` does not properly run outgoing
`dynamic-wind` thunks; and `cons` produces what Racket sees as `mcons`, which
"will bite you when you pass lists over the R7RS-Racket boundary" **[doc]**.
Against §1.2 the first three are inert here (`include-ci` 0, `dynamic-wind` 0),
and the mutable-pair representation is a printing/interop concern rather than a
correctness one because the tree never mutates a pair **[inf]**. So "port the
R7RS tree" is a bounded option rather than a rewrite — but it rests on a
third-party package, not a core-supported path, and that should not be quietly
dropped.

**Cost.** From the implementation author's own **January 2018** report: Racket CS
440 ms bare startup, 550 ms `-l racket/base`, 1 200 ms `-l racket`, against BC's
16/50/220 ms, attributed to Chez boot-file loading plus loading the expander;
executable size roughly doubled 30 MB → 70 MB from BC to CS for `racket/gui`
**[doc]**. **Eight years old, taken mid-development; current-release numbers not
found — [gap].** A resident runtime pays startup once at app launch, not per
leader press (§2.3), so 440 ms is an app-launch line item **[inf]**.

**Walk-away check:** depends which Racket. A `#lang s-exp` module language leaves
s-expressions on disk; a reader-extended `#lang` makes the reader the only thing
that can parse the file — the worst walk-away result in the set **[inf]**.

### 4.3 Common Lisp, on SBCL

**Language vs implementation.** Common Lisp is the ANSI standard; SBCL is one
implementation. The distinction is load-bearing precisely here, because embedding
is entirely an implementation property and SBCL's is the weakest of the mature
ones.

**Embedding is documented in the primary manual**, not only in third-party
tooling: §9.8 *Calling Lisp From C* and §9.8.1 *Lisp as a Shared Library* cover
the host-side entry point `initialize_lisp` and shared-library support, and
§9.8.1 records a **lifecycle limitation that matters more than the mechanics** —
C cannot currently run exit hooks or gracefully undo Lisp initialisation
**[doc]**. An embedded runtime that cannot be shut down cleanly is an
app-lifetime commitment, which is a real argument for a restartable helper
*process* over in-process embedding, and it applies to Modaliser's
reload-by-relaunch doctrine directly. Functions are described with
`sb-alien:define-alien-callable` and listed in `save-lisp-and-die`'s
`:callable-exports`, letting C bind into a Lisp core with the ordinary C calling
convention; the surrounding tooling requires SBCL > 2.1.10 **[doc]**.
arm64-darwin is supported and actively maintained (binaries from 2.1.2; ongoing
arm64 fixes, including moving the static space address on macOS) **[doc]**.

**Why it fits this host badly.** Three documented properties, each colliding with
something Modaliser already does:

| Property **[doc]** | Collision **[inf]** |
|---|---|
| The runtime installs **signal handlers into the process** for keyboard interrupts, and on some platforms a stop-the-world GC signal | An AppKit app with a CGEventTap on a dedicated thread and a main-queue evaluation fence; process-wide signal handlers are a shared resource with no owner |
| On Intel macOS you **must** link with `-pagezero_size 0x100000` or SBCL cannot mmap its static space at `0x5000000` | A linker flag on Modaliser's own executable, driven by the guest runtime's fixed-address requirement. The arm64 equivalent was not established — **[gap]** |
| Its own GC and allocator | A tracing collector alongside Swift's reference counting (ARC is not a tracing GC) and, if coexisting, LispKit's |

**Artifact shape.** The deliverable is a saved core — a large opaque binary.
No primary figure for a minimal arm64-darwin core size was obtained — **[gap]**.

**The fairer Common Lisp.** ECL (Embeddable Common-Lisp) is designed for this
role and its manual carries a dedicated "Embedding ECL" section **[doc]**; the
concrete entry points, link target and platform matrix were not confirmed from
primary sources in this pass — **[gap]**. If Common Lisp is wanted for the
language, ECL rather than SBCL is where the evaluation should start, and the
brief's phrasing ("Common Lisp on SBCL") should be read as naming a language
first and an implementation second.

**Walk-away check:** the *source* is s-expressions and survives fine; the
*delivered artifact* is a core image no one can read, and idiomatic CL configs
lean on macros, which means the authored file's meaning may not be recoverable
without the macro definitions **[inf]**.

### 4.4 TypeScript, on JavaScriptCore

TypeScript is not a runtime, so this is scored as **TypeScript source →
type-stripping or `tsc` → JavaScriptCore `JSContext`**, which is the shape with
the lowest hosting cost available for this candidate.

**Runtime.** JavaScriptCore is a system framework. The **public** Objective-C
surface is `JSContext` and `JSValue` — WebKit's Xcode project installs
`JSContext.h` and `JSValue.h` with `ATTRIBUTES = (Public, )` **[doc]** — which
gives string evaluation via `evaluateScript:`, host functions installed as
blocks, and value bridging.

**Both the module loader and `JSScript` are private API, and this is decisive.**
`moduleLoaderDelegate`, the `JSModuleLoaderDelegate` protocol,
`evaluateJSScript:` and `dependencyIdentifiersForModuleJSScript:` are declared in
`JSContextPrivate.h`; and `JSScript.h` **itself** is installed
`ATTRIBUTES = (Private, )` in the same project file **[doc]**. So
`kJSScriptTypeModule`, `cacheBytecodeWithError:` and the memory-mapped source
constructor are all off the supported path — the bytecode cache is **not** a
public startup lever, and the earlier draft of this survey was wrong to call it
one. **A `JSC_CLASS_AVAILABLE` annotation records an OS version floor, not API
visibility**; the header's install attribute is what settles that, and it is the
check to apply to any future JSC claim.

A shippable TypeScript tier on public JSC therefore has **no module system and no
bytecode cache**: the config is a single script string, or the host implements
its own resolution (a `require`-style shim over host file reads), or the config is
bundled before evaluation **[inf]**.

**Packaging, corrected twice.** There is nothing to vendor and no boot files, so
the runtime artifact is still the cheapest in the set. But there is no
tooling-free case: TypeScript is not executable, so **something must strip the
types** — either the app ships a stripper and does it at load, or the user runs a
transform while authoring. Choosing a single file or a module shim removes the
module problem, not this one **[inf]**. Note also that the WebView's JavaScript
runs **out of process** under WebKit's architecture, so an in-process `JSContext`
is a separate engine, not a reuse of the renderer's **[inf]**.

**Transform pipeline.** TypeScript 5.8's `erasableSyntaxOnly` forbids the
constructs that cannot be erased — `enum`, `const enum`, `namespace`, parameter
properties — precisely so code can be processed by tools that strip types without
changing semantics; `verbatimModuleSyntax` emits import/export as written
**[doc]**. Authoring under both means type-stripping suffices, so no *compiler*
is needed at runtime **[inf]**. That removes `tsc` from the runtime path; it does
not remove the module problem above, and `verbatimModuleSyntax` is of limited
help when the emitted `import` has no supported loader to receive it.

**Where it fights the host.** ADR-0018's handoff validates once and latches on
success — a synchronous, one-shot commit. Module loading and top-level `await`
are asynchronous and JSC's microtask queue needs draining, so a JS configuration
tier needs an explicit pump and a defined "configuration is complete" point or
the latch has nothing coherent to latch **[inf]**. A host-written synchronous
module shim would sidestep both this and the private-API problem at once, which
is worth weighing against ESM's familiarity **[inf]**.

**Tooling**, the strongest of the five: a type checker the user already has,
mainstream LSP, and the one candidate where "what can this facility do?" is
answerable by autocomplete over a generated `.d.ts` **[inf]**. It would be typing
a surface currently expressed as 308 `(assoc`s over untyped alists — a gain the
baseline could not have.

**Walk-away check:** good. `.ts` files are readable text, and under
`erasableSyntaxOnly` the runtime form differs from the authored form only by
deleted annotations **[inf]**.

### 4.5 Lua

**Embedding** is Lua's design centre. The C API takes a `lua_State*` as the first
argument to every function; the implementation "runs by interpreting bytecode
with a **register-based virtual machine**" — a plain interpreter, no JIT
**[doc]**. Current release **Lua 5.5.1** (2026-08-03); 5.5.0 shipped 2025-12-22
and 5.4.9 (2026-08-25) closes the 5.4 line **[doc]**. Swift can call the C API
directly through a module map — but that supplies *calling*, not a bridge: value
marshalling, rooting against Lua's collector, callback ownership and safe error
unwinding all remain host code to write **[inf]**. "No bridging layer" would be
the wrong conclusion; the right one is that the bridge is small, explicit and
unhidden.

**It addresses baseline defect (b) at the host's own entry point.** Protected
evaluation is **not** unique to Lua — Common Lisp has conditions and restarts,
Racket has `with-handlers`, JavaScript has `try`/`catch`. Lua's distinctive
property is *where* the protection sits: `lua_pcall`/`lua_pcallk` are **C API**
calls, so the status code (`LUA_ERRRUN`, `LUA_ERRMEM`, …) is returned to the
**host**, which is precisely the shape ADR-0022 needed and could not get from
LispKit **[doc]** **[inf]**.

**And it carries a Swift-specific obligation.** Lua implements error propagation
with `longjmp` by default, using C++ exceptions only when compiled as C++
(`LUAI_THROW`); an error destroys the C frames between the raise and the
enclosing protected call **[doc]**. Unwinding by `longjmp` across Swift frames is
not something a Swift host may rely on, so a Lua tier owes a defined protected
boundary — no Swift frames between `lua_pcall` and the erroring code, or a C++
build — before defect (b) is actually answered in this host. Not established
here; it is a design obligation and an experiment, not a given **[gap]**.

**Holding closures** needs host marshalling and explicit lifetime, not just a
handle. The registry at `LUA_REGISTRYINDEX` plus `luaL_ref` gives an integer
handle to any Lua value, functions included **[doc]**, which fits §2.1's two
registries — but the handle must be released explicitly, so each registry becomes
an owner with a teardown path, exactly as a locked Racket handle vector does
**[inf]**. Neither candidate makes cross-boundary lifetime free; both document a
mechanism for it.

**Async and the run loop.** No event loop, no async I/O; coroutines only,
resumed via `lua_resume` and yielding via `lua_yieldk` **[doc]**. For a passive
evaluator called from the main queue (§2.3) that is the right shape — Lua never
wants the run loop.

**Sandboxing and modules.** A chunk loads with a different `_ENV` via
`load`/`loadfile`, so the host decides exactly what user code can see **[doc]**
— a stronger mechanism for the decision-free contract than the grep
`check-decision-free.sh` uses today. Module resolution is `require` over
`package.path`/`package.cpath`; the searcher-replacement API was not confirmed
from the 5.5 manual excerpt obtained — **[gap]**.

**Weaknesses.** No static types (LuaCATS plus `lua-language-server` are the
community answer, unverified here — **[gap]**); 1-based indexing and
`nil`-as-absent are a real ergonomic shift; adoption means discarding 24 000
lines of Scheme or running two runtimes. **LuaJIT is a different proposition** —
5.1-compatible and JIT-based, reintroducing the executable-memory question plain
Lua avoids.

**Walk-away check:** the best of the four alternatives. A config is plain Lua
tables and functions that any Lua runs, with no build step and no reader
extension between the text and its meaning **[inf]**.

---

## 5. Comparison

### 5.1 Hosting and packaging

| | LispKit | Racket CS | SBCL | TS on JSC | Lua 5.5 |
|---|---|---|---|---|---|
| What the app links | Swift package | Racket framework **[doc]** | SBCL core as shared lib **[doc]** | system framework | ~1 C library |
| Runtime artifact to ship | none | framework + 3 boot files **[doc]** | saved core **[gap]** on size | none | none of consequence |
| Executes generated machine code | no | yes (Chez) | yes | yes (JSC JIT) | **no** (bytecode VM **[doc]**) |
| Installs process signal handlers | no | **[gap]** | **yes** **[doc]** | no | no |
| Own tracing collector, alongside ARC's reference counting | yes | yes | yes | yes | yes |
| Wants the run loop | no | no | no | no (with a pump) | no |
| Toolchain in the *user's* install path | none | `raco` if used as front end | a Lisp | a type-stripper always — shipped in-app or run while authoring **[inf]** | none |
| Documented startup figure | **[gap]** | 440–1 200 ms, **Jan 2018** **[doc]** | **[gap]** | bytecode cache is **private API** **[doc]**; no figure **[gap]** | **[gap]** |

**One conditional cost applies to four of five and is currently dormant.**
`build-app.sh` signs with a self-signed "Modaliser Dev" identity or ad-hoc, with
**no entitlements file, no `--options runtime`, and no notarisation** anywhere in
`scripts/` or `docs/RELEASING.md` **[src]**. So the JIT-entitlement question
(`com.apple.security.cs.allow-jit` under hardened runtime) does not bite today.
It becomes load-bearing the moment the project notarises — plausible for a public
release — and at that point Racket, SBCL, JavaScriptCore and LuaJIT all execute
generated code while LispKit and plain Lua do not. The precise entitlement
requirement per runtime was **not** verified: Apple's documentation pages did not
render for retrieval — **[gap]**. Flagging it as a conditional, unmeasured cost
is the honest position; treating it as settled either way would not be.

### 5.2 Against the three measured baseline defects

| Defect (§1.3) | Racket | SBCL | TS on JSC | Lua |
|---|---|---|---|---|
| (a) Θ(n) `string-ref` | fixed — immutable strings, indexed access | fixed | strings are JS strings; index access is ordinary | fixed; Lua strings are immutable byte strings, but are **byte**-indexed, so Unicode handling moves to the author **[inf]** |
| (b) No protected re-entrant evaluation | `with-handlers` in-language; **[gap]** on nesting through the C API | conditions + restarts, the richest of the five | `try`/`catch`, and host-side exception objects | `lua_pcall` puts it at the **C API**, so the host gets the status — but owes a `longjmp`-safe boundary **[doc]** **[gap]** |
| (c) Immutable pairs / thin stdlib | `#lang r7rs` inverts it: `cons` is `mcons` **[doc]**; large stdlib | mutable conses, very large stdlib | mutable everything, large stdlib | mutable tables; small stdlib, `table.sort` present |

### 5.3 The required dimensions

| | LispKit | Racket | SBCL | TS on JSC | Lua |
|---|---|---|---|---|---|
| Ordinary composition | good (measured: procedures + alists) | good | good | good | good |
| Callback closures, captured state | native | native; retain via `Slock_object` or one locked handle vector **[doc]** | native | native | native; `luaL_ref` handles, released explicitly **[doc]** |
| Dynamic providers | current design | fine | fine | fine | fine |
| Async work | none used; host-sequenced | futures/threads available | threads | **promises/microtasks — needs a pump vs ADR-0018** **[inf]** | coroutines, host-driven **[doc]** |
| Errors | **defect (b)** | handlers | conditions + restarts | exceptions | `lua_pcall` |
| Module resolution | R7RS `define-library`, host search path | `#lang` + collections | ASDF/packages | **ESM and `JSScript` are both private API**; publicly, host shim or bundle **[doc]** | `require`/`package.path` **[gap]** on searcher API |
| Native interop | 16 Swift libraries today | C API + object locking | `sb-alien`; `initialize_lisp`, no clean shutdown (§9.8.1) **[doc]** | public `JSContext`/`JSValue` only | C API from Swift; marshalling, rooting and a `longjmp` boundary are host code |
| Tooling / diagnostics | LispPad; no LSP found **[gap]** | DrRacket, contracts, langserver **[gap]** on current state | SLIME/SLY | **strongest**: tsc + mainstream LSP | `lua-language-server`, LuaCATS **[gap]** |
| Packaging | nothing to do | framework + boot files | core image | nothing to do | nothing of consequence |
| Host event-loop ownership | passive | passive | **signal-handler intrusion; no graceful de-initialisation** **[doc]** | passive with a pump | passive |

---

## 6. The two scenarios

### 6.1 Editor group

The layout/grouping half is data in every candidate — a nested record with
titles, spans and an ordering. That is not where candidates differ.

The **provider** is. `editor-provider` gathers at come-to-rest, mints per-visit
tokens and assigns jump labels, and the paired `part-list` block never queries:
its render hook reads the cell the provider filled, which is what makes rows and
live labels unable to disagree (`app-facilities-a.md` §1, from source). That
needs a value the host can call at come-to-rest, per-visit state whose lifetime
is the visit, and a render hook that reads rather than re-queries.

All five candidates express this directly as a resident runtime. **A serialised
front end cannot**, because the provider is behaviour; it can only *name* a
library-provided provider, which returns us to §3's option 2 and its cost.

### 6.2 Cross-facility action (Grove Leaf)

`focused-workspace-path` knows only VS Code; `grove:live-leaf` knows only grove;
the user's config joins them in an `and`-chain with its own missing-value
message. This is the scenario that discriminates hardest, and along one axis
only: **does the user get to author a novel join?**

| Shape | Grove Leaf outcome |
|---|---|
| Resident runtime, any candidate | works; the join is ordinary code, and the `and`-chain becomes `&&`, `and`, or nested `if` |
| Declarative front end + **named operations only** | **fails unless the library ships this join.** The user can select and parameterise, not compose |
| Declarative front end **with an expression language** | works, at the cost of designing and shipping that language. A data representation may carry sequencing, conditionals, bindings and expressions; what it cannot carry is a *resident closure the host calls back into* unless it also defines evaluation semantics for one. The question is therefore not "declarative or not" but **how much interpreter the data format contains** — and every increment of it is language design work, diagnostics included **[inf]** |
| Process-separated facilities, resident composition tier | works, but the async completion becomes explicit — awaits, callbacks, or coroutine yields — and missing-value handling must survive a boundary that can also time out **[inf]** |

The third row is the one a design must think hardest about, because §2.2 shows
the repo already has a working async data-plus-callback boundary for the
renderer, and it is tempting to conclude the same shape suits composition. Hold
onto the Grove Leaf chain as the counter-example: it is short, synchronous in
expression, and its whole value is that two unrelated facilities compose without
either knowing the other.

---

## 7. Migration, coexistence, and one promise not to make

**Do not promise all four.** A language-neutral facility contract is attractive
and is a legitimate design target for axis 3. Shipping four language runtimes is
a different commitment, and the multiplier is not the runtimes — it is
diagnostics, packaging, the decision-free contract, and the outward-seam
quarantine, each of which currently has exactly one enforcement mechanism.
`check-portable-surface.sh` and `check-decision-free.sh` are directory-scoped
greps over `.sld` files **[src]**; every additional language needs its own
answer to "what enforces this here", or an explicit statement that it does not
apply. That is per-language recurring cost, not one-time cost **[inf]**.

**Coexistence shapes, cheapest first:**

| Shape | Cost |
|---|---|
| Keep LispKit; fix (a) and (c) locally, pursue (b) upstream as ADR-0022 names | lowest; no new runtime, and the only shape needing no user migration |
| Keep LispKit as the library tier; add one candidate as the *config* tier over a defined protocol | two runtimes, one protocol, users choose; §6.2's third row is the risk |
| Port the R7RS tree to a host claiming R7RS | bounded by §1.2 and gated on §4.2's package caveats; keeps the language, changes the implementation |
| Full replacement in a non-Scheme candidate | 24 000 lines, plus every seam, quarantine and invariant check re-established |

**Migration of user configs.** ADR-0019 keeps `config.scm` as the *only*
user-owned file, so machinery is always fresh and only preference can go stale. A
language change invalidates 100 % of that one file at once — the largest single
migration event the current architecture admits — and ADR-0022's degradation path
is what makes it survivable, so it is a precondition rather than a nicety
**[inf]**.

**Hot reload stays out.** No candidate's REPL is an argument for it: ADR-0018
rejected reload on orphan-state grounds and ADR-0022's fallback is defined as
"nothing was ever installed". Any proposal to revisit it must be made explicitly
on ADR-0018's own reopening terms.

---

## 8. Conditional recommendations

**If the goal is to fix what is measurably wrong (recommended first move):**
keep LispKit, and treat §1.3 as three separable work items — vector-scan the
remaining 24 `string-ref` sites, close the stdlib gaps locally as `util.sld`
already does, and pursue re-entrant protected evaluation upstream, which
ADR-0022 already names as its reopening condition. This is the only option with
no migration event, and nothing in this survey found a defect that *requires* a
language change. Closing the `branch: "master"` pin (§1.4) belongs here too, and
is worth doing regardless of every other conclusion in this survey.

**If the goal is a better user-facing authoring surface:** TypeScript on
JavaScriptCore, but **more conditionally than it first appears**. Its opportunity
is real: typed facilities, where autocomplete over a generated `.d.ts` answers
"what can this app do?" in a way 308 untyped `(assoc`s cannot. Racket contracts
and SBCL's compile-time type warnings are also real type discipline — the
TypeScript claim is specifically about *mainstream editor tooling the user
already runs*, not about being the only typed candidate. Its runtime is a system
framework with nothing to vendor.

Against that, **both JSC's module loader and `JSScript` are private API**
(§4.4), which costs more than it first looks: no supported ES modules *and* no
public bytecode cache, so the startup lever this option seemed to offer is not
available. A shippable design must choose up front between a single-file config,
a host-written module shim, or bundling — and in every case something must strip
the types, in-app or while authoring. Those are design decisions this survey
cannot make, and they should be settled before the option is costed. The
async/handoff pump of §4.4 is the remaining obligation.

**If the goal is the smallest, most robust embedded runtime:** Lua. Its case is
that protected evaluation sits at the **C API**, so the host receives the status
code — the shape ADR-0022 wanted — rather than that protected evaluation is rare;
every candidate has some form of it. Add a plain bytecode VM with no generated
machine code, a packaging cost of about one C library — effectively nil, and on a
par with JSC's system framework — and `_ENV`, which gives the decision-free
contract an enforcement mechanism stronger than a grep. Its
obligations are a `longjmp`-safe boundary against Swift frames and explicit
handle lifetimes (§4.5); its cost is discarding or double-hosting 24 000 lines of
Scheme, and no static types.

**If the goal is language-oriented programming:** Racket, and specifically
`#lang` — not because it is the only way to design a notation (CL reader macros
and a host-written parser also are) but because the reader and the expander are
selected per file and scoped to it (§4.2). Weigh that against the
framework-plus-boot-files packaging, the object-locking discipline for retained
handles, the dated startup figures, and the fact that §1.2 measured three macros
in the entire tree — the project has not so far needed the power `#lang` sells.

**Not recommended as scoped:** Common Lisp *on SBCL*. Process-wide signal
handlers, a fixed-address static space that on Intel macOS requires a linker flag
on Modaliser's own executable (arm64 equivalent unestablished — §4.3), a **second
tracing collector** in a process that already has LispKit's — Swift's ARC is
reference counting, not a tracing GC, so it is not one of the count — an opaque
core artifact, and — per §9.8.1 — no way for C
to run exit hooks or gracefully undo Lisp initialisation are a poor fit for an
AppKit app with an event tap and a relaunch-based reload doctrine. If Common Lisp
is wanted for the language, evaluate ECL rather than SBCL, and weigh a
restartable helper process against in-process embedding.

**What would change these:** a measured current-release Racket CS startup figure
under 100 ms; a LispKit release with re-entrant protected evaluation *and* O(1)
`string-ref`, which would remove most of the case for moving; a decision that the
config surface should be declarative-with-named-operations, which makes the
runtime choice nearly free and makes multi-language plausible — at the cost of
§6.2; or a decision to notarise, which prices the JIT/entitlement column in §5.1
that is currently dormant.

---

## 9. Gaps, silences, and what design must settle

**Silences — searched for, not found.** No primary current-release Racket CS
startup or minimal-distribution-size figure (only the author's January 2018
report). No primary figure for a minimal arm64-darwin SBCL core size. The SBCL
manual's §9.8/§9.8.1 bodies did not render, so `initialize_lisp` and the
shared-library mechanics are cited by section rather than read. No primary
confirmation of ECL's embedding entry points or link target. No primary
confirmation of Apple's per-runtime JIT-entitlement requirements — the relevant
documentation pages did not render for retrieval. No LSP for LispKit found. No
primary source for the Lua module-searcher replacement API in the 5.5 manual, nor
for `lua-language-server`/LuaCATS capabilities. Recording these stops the next
reader repeating the same searches.

**Unmeasured here — every one of them needs an experiment, not more reading.**
Startup cost of any candidate inside a `.app`; resident memory of two runtimes;
overlay latency under a leader press for any candidate; packaged `.app` size
delta; whether LispKit's `string-ref` cost is fixable upstream or intrinsic to
the `NSMutableString` backing; whether Racket CS's retain caveat is tractable for
the two registries in §2.1; whether SBCL's arm64-darwin build needs the Intel
`-pagezero_size` equivalent.

**Questions research can settle:** the remaining §5 **[gap]** cells, all of them
documentation lookups.

**Questions only the user can settle:** whether the config surface stays
Turing-complete or becomes declarative-with-named-operations (this is the single
highest-leverage decision in the leaf, and §6.2 is its test case); whether static
types in the config are worth a language change; whether s-expressions are a
value to preserve or an obstacle to remove; whether notarisation is on the
roadmap.

**Claims that would need an experiment before an ADR could rest on them:** any
statement that a candidate is fast enough, small enough, or that two runtimes
coexist without incident. Nothing in this survey establishes any of those, and
the leaf's instruction was to record the gap rather than expand the research to
close it.

**How to re-verify §1.2 and §2.1.** Those counts were taken with `/usr/bin/grep`
under a positive control (`define` → 1 536) and a negative control
(`zzz-absent-zzz` → 0), because two earlier readings exited 0 and printed
plausible, meaningless numbers — `grep` and `cat` are aliased here, and zsh does
not word-split unquoted parameter expansions. Re-establish both controls rather
than trusting the figures.

---

## Sources

External, all consulted **2026-09-10**:

- Racket, *Inside: Racket C API* — [Embedding into a Program (CS)](https://docs.racket-lang.org/inside/cs-embedding.html); [Overview (CS)](https://docs.racket-lang.org/inside/cs.html); [Values and Types (CS)](https://docs.racket-lang.org/inside/cs-values_types.html) (`Slock_object`, locked handle vector)
- Racket Guide — [Creating Languages](https://docs.racket-lang.org/guide/languages.html)
- Matthew Flatt, [*Racket-on-Chez Status: January 2018 (extended)*](https://users.cs.utah.edu/~mflatt/racket-on-chez-jan-2018/) — startup and memory figures, **dated**
- [`lexi-lambda/racket-r7rs`](https://github.com/lexi-lambda/racket-r7rs) and [`lassik/racket-r7rs-example`](https://github.com/lassik/racket-r7rs-example) — `#lang r7rs` coverage and caveats
- [`quil-lang/sbcl-librarian`](https://github.com/quil-lang/sbcl-librarian) — SBCL shared-library constraints, `:callable-exports`, `-pagezero_size`, signal handlers
- [SBCL manual](https://www.sbcl.org/manual/) §9.8 *Calling Lisp From C*, §9.8.1 *Lisp as a Shared Library* (`initialize_lisp`; section bodies not retrieved); [SBCL releases](https://github.com/sbcl/sbcl/releases) — arm64-darwin platform support
- [Embeddable Common-Lisp](https://ecl.common-lisp.dev/) and its [manual](https://ecl.common-lisp.dev/static/manual/Overview.html)
- TypeScript — [tsconfig reference](https://www.typescriptlang.org/tsconfig/): `erasableSyntaxOnly` (5.8), `verbatimModuleSyntax`
- WebKit — [`JavaScriptCore.xcodeproj/project.pbxproj`](https://raw.githubusercontent.com/WebKit/WebKit/main/Source/JavaScriptCore/JavaScriptCore.xcodeproj/project.pbxproj): `JSScript.h in Headers` is `(Private, )`, `JSContext.h`/`JSValue.h` are `(Public, )` — the check that settles API visibility; [`JSContextPrivate.h`](https://raw.githubusercontent.com/WebKit/WebKit/main/Source/JavaScriptCore/API/JSContextPrivate.h) (`moduleLoaderDelegate`, `JSModuleLoaderDelegate`, `evaluateJSScript:`); [`JSScript.h`](https://raw.githubusercontent.com/WebKit/WebKit/main/Source/JavaScriptCore/API/JSScript.h)
- Lua — [5.4 manual](https://www.lua.org/manual/5.4/manual.html), [5.5 manual](https://www.lua.org/manual/5.5/manual.html), [version history](https://www.lua.org/versions.html)
- [`objecthub/swift-lispkit`](https://github.com/objecthub/swift-lispkit) — purpose, R7RS incompatibilities, SRFI-18

Local, at `a97a1bf2`: `Package.swift`, `Package.resolved`,
`Sources/Modaliser/SchemeEngine.swift`, `KeyboardLibrary.swift`,
`KeyboardCapture.swift`, `KeyboardHandlerRegistry.swift`, `WebViewLibrary.swift`,
`LifecycleLibrary.swift`, the 16 `*Library.swift` files,
`Scheme/lib/modaliser/instrument.sld`, `dsl.sld`, `fsm.sld`, `util.sld`,
`terminal.sld`, `theming.sld`, `window-actions.sld`, `apps/vscode.sld`,
`muxes/herdr.sld`, `Scheme/root.scm`, `Scheme/ui/overlay.scm`,
`scripts/build-app.sh`, `docs/adr/0022-config-failure-degrades.md`,
`docs/research/configuration-exploration-context.md`,
`docs/research/app-facilities-a.md`.
