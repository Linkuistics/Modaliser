// One counter, one map, a kind tag on every entry
// (docs/specs/vscode-window-parts.md, decision 4; ADR-0027).
//
// A target's identity is the pair (peer, token), and the peer half is the
// reply's business. This is the token half, and three properties make it an
// identity rather than an index:
//
// ONE COUNTER, NEVER RESET. Terminals and editors allocate from the same
// counter and share one map, so a terminal's token handed to `focus-editor`
// *resolves* — and is refused by the kind tag. Two independently numbered
// spaces would both hand out `3`, so the same integer would be live in both at
// once and a kind confusion would land on a real object of the other kind
// instead of being refused. One counter removes the collision; the tag is what
// turns a wrong-kind token into a refusal. This is why `lookup` takes a kind:
// cross-kind refusal is the *same code path* as stale-token refusal, not a
// hope that the lookup will helpfully fail.
//
// PRUNE, NEVER REPLACE. A `parts` call drops the entries whose object is gone
// and leaves every other token alone. Replacing the map wholesale is wrong for
// a reason that is invisible until two panels exist: the screen's two
// providers each call `parts`, so the second call would invalidate the tokens
// the first panel's rows were just drawn with, and every label on that panel
// would silently do nothing.
//
// KEYED ON OBJECT IDENTITY — a stated assumption, not a guarantee. `Terminal`
// is a stable object and the API says as much. For `Tab` the shipped
// declarations promise only that `close()` invalidates one; nothing there says
// a `Tab` object survives a structural change to the tab model. It does in
// VSCode 1.136.2 — the extension host memoises each API `Tab` and reconciles
// by a stable internal tab id, so dirty/pinned/active/moved updates reuse the
// wrapper. If a future VSCode re-materialises `Tab` objects, identity-keyed
// pruning drops live entries on the next `parts` and the second panel's labels
// stop working while nothing else looks wrong; the fallback is to key on a
// value instead — the tab's URI plus its group. `test/registry.test.ts` is
// where that assumption is pinned, because it is invisible from Modaliser's
// side.

export type PartKind = "terminal" | "editor";

interface Entry {
  readonly token: number;
  readonly kind: PartKind;
  readonly object: object;
}

export class TokenRegistry {
  /** Never reset, for the life of this extension instance. A socket name is
   *  never reused either (ADR-0027), so a token from a previous instance
   *  cannot arrive here at all — which is why this counter needs no global
   *  uniqueness. */
  private nextToken = 1;
  private readonly byToken = new Map<number, Entry>();
  private readonly byObject = new Map<object, Entry>();

  /** The token for OBJECT, minting one if it has not been seen. Stable across
   *  any number of `parts` calls for as long as the object is live. */
  tokenFor(object: object, kind: PartKind): number {
    const existing = this.byObject.get(object);
    if (existing !== undefined && existing.kind === kind) {
      return existing.token;
    }
    const entry: Entry = { token: this.nextToken++, kind, object };
    this.byToken.set(entry.token, entry);
    this.byObject.set(object, entry);
    return entry.token;
  }

  /** Drop the entries whose object is no longer among LIVE. Called from
   *  `parts` and nowhere else, which is exactly why the focus methods still
   *  have to check membership: between a read and a press a closed part is
   *  still mapped. */
  prune(live: Iterable<object>): void {
    const alive = new Set<object>(live);
    for (const [object, entry] of this.byObject) {
      if (!alive.has(object)) {
        this.byObject.delete(object);
        this.byToken.delete(entry.token);
      }
    }
  }

  /** The object TOKEN names, if it names one *of that kind*. Undefined for a
   *  token that was never minted, for one whose object has been pruned, and
   *  for one that names the other kind — one refusal path for all three. */
  lookup(token: unknown, kind: PartKind): object | undefined {
    if (typeof token !== "number" || !Number.isInteger(token)) {
      return undefined;
    }
    const entry = this.byToken.get(token);
    if (entry === undefined || entry.kind !== kind) {
      return undefined;
    }
    return entry.object;
  }

  /** Test-visible size, so a pruning test asserts the map rather than its
   *  effects. */
  get size(): number {
    return this.byToken.size;
  }
}
