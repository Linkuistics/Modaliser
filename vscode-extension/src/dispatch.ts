// One line in, at most one line out
// (docs/specs/vscode-window-parts.md, decision 2).
//
// This is the whole method table, and it is deliberately three entries long.
// A `commands.executeCommand` passthrough is one line and would turn a bounded
// question-answering peer into a remote control for the workbench; ADR-0026
// enumerates exactly what this surface exposes and accepts, so if a fourth
// method is ever wanted, that record is what has to change first.
//
// `parts` is answered. The two focus methods are answered with NOTHING — not
// an `{"ok": …}`, not an error envelope — so `dispatch` returns null for them
// and the caller writes nothing (ADR-0014).

import { focusEditor, focusTerminal } from "./actions";
import { buildParts } from "./parts";
import type { PeerEnv } from "./peerEnv";
import type { WireRequest } from "./protocol";
import {
  METHOD_FOCUS_EDITOR,
  METHOD_FOCUS_TERMINAL,
  METHOD_PARTS,
} from "./protocol";
import type { TokenRegistry } from "./registry";

function tokenOf(params: unknown): unknown {
  if (typeof params !== "object" || params === null) {
    return undefined;
  }
  return (params as { token?: unknown }).token;
}

/** LINE → the reply line to write, or null when the method answers nothing (or
 *  when there is nobody to answer: an unparseable line carries no id).
 *
 *  Never throws. A peer that threw out of a socket callback would take the
 *  connection down with a reason Modaliser cannot see, and Modaliser's own
 *  contract is that a leader press never raises; matching it here means a
 *  malformed request is a logged non-event on both sides. */
export async function dispatch(
  env: PeerEnv,
  registry: TokenRegistry,
  line: string,
): Promise<string | null> {
  let request: WireRequest;
  try {
    request = JSON.parse(line) as WireRequest;
  } catch {
    env.log(`ignored an unparseable request: ${line.slice(0, 200)}`);
    return null;
  }
  if (typeof request !== "object" || request === null) {
    env.log("ignored a request that was not an object");
    return null;
  }

  const id = request.id ?? null;
  const method = request.method;

  try {
    switch (method) {
      case METHOD_PARTS:
        return JSON.stringify({ id, result: buildParts(env, registry) });

      // Both notifications swallow their own failures. Letting one fall
      // through to the error envelope below would put bytes on a wire the
      // contract says stays silent — and there is nobody to read them:
      // `unix-socket-send` has closed its end before the activation even
      // starts. The log line is the whole of the report, as it is for a
      // refusal.
      case METHOD_FOCUS_TERMINAL:
        try {
          focusTerminal(env, registry, tokenOf(request.params));
        } catch (error) {
          env.log(`focus-terminal failed: ${String(error)}`);
        }
        return null;

      case METHOD_FOCUS_EDITOR:
        try {
          await focusEditor(env, registry, tokenOf(request.params));
        } catch (error) {
          env.log(`focus-editor failed: ${String(error)}`);
        }
        return null;

      default:
        // A method this peer does not have. Answered rather than ignored: an
        // unknown method may well be a QUERY from a newer Modaliser, and a
        // caller waiting for a reply should get one rather than a timeout.
        // A caller that was not waiting closed its end already and the write
        // is discarded, which costs nothing.
        env.log(`unknown method: ${String(method)}`);
        return JSON.stringify({
          id,
          error: { message: `unknown method: ${String(method)}` },
        });
    }
  } catch (error) {
    // Only `parts` and the unknown-method branch can reach here; both are
    // queries, so an envelope is the right answer.
    env.log(`${String(method)} failed: ${String(error)}`);
    return JSON.stringify({ id, error: { message: String(error) } });
  }
}
