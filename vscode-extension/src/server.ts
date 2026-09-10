// The socket itself: connect-per-request, one line each way
// (ADR-0020, reused unchanged; docs/specs/vscode-window-parts.md, decision 2).
//
// Modaliser's `unix-socket-request` / `unix-socket-send` own the newline
// framing on their side and expect the same here: one request line in, at most
// one reply line out, then close. There is no pool, no keep-alive and no id
// correlation to track — one request per connection is trivially one-to-one.

import * as net from "node:net";
import { dispatch } from "./dispatch";
import type { PeerEnv } from "./peerEnv";
import type { TokenRegistry } from "./registry";

/** A connection that has said nothing for this long is abandoned. Modaliser's
 *  own read gives up at 200 ms, so anything still open here is not a caller
 *  waiting for an answer. */
const CONNECTION_IDLE_MS = 5000;

/** The most a single request line may be. A request is `{"id","method",
 *  "params":{"token":N}}` — tens of bytes — so this is four orders of
 *  magnitude of headroom, and it exists so a peer that never sends a newline
 *  cannot grow this buffer without bound. */
const MAX_REQUEST_BYTES = 64 * 1024;

export function createServer(env: PeerEnv, registry: TokenRegistry): net.Server {
  const server = net.createServer((socket) => {
    let buffer = "";
    let handled = false;

    socket.setEncoding("utf8");
    socket.setTimeout(CONNECTION_IDLE_MS, () => socket.destroy());
    // A caller that abandoned its reply has already closed its end, so a
    // write can land on a closed pipe. That is the normal notification path,
    // not a fault.
    socket.on("error", (error) => env.log(`connection error: ${String(error)}`));

    socket.on("data", (chunk: string) => {
      if (handled) {
        return;
      }
      buffer += chunk;
      if (buffer.length > MAX_REQUEST_BYTES) {
        env.log("request exceeded the maximum line length; dropping it");
        socket.destroy();
        return;
      }
      const newline = buffer.indexOf("\n");
      if (newline < 0) {
        return;
      }
      handled = true;
      // Anything after the first line is discarded: one message per
      // connection is the model.
      const line = buffer.slice(0, newline);
      void dispatch(env, registry, line).then(
        (reply) => {
          if (reply !== null && !socket.destroyed) {
            socket.end(`${reply}\n`);
          } else {
            socket.end();
          }
        },
        (error) => {
          // `dispatch` is written not to reject; this is the belt on top of
          // the braces, because an unhandled rejection in the extension host
          // is a report the human has to go looking for.
          env.log(`dispatch rejected: ${String(error)}`);
          socket.end();
        },
      );
    });
  });

  server.on("error", (error) => env.log(`socket server error: ${String(error)}`));
  return server;
}
