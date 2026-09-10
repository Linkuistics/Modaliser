// Tidying up after a crashed extension host
// (docs/specs/vscode-window-parts.md, decision 3; ADR-0027).
//
// Because a socket name is never reused, a host that died leaves its socket
// file behind and nothing will ever bind that name again. So the tidy-up is a
// SWEEP at activation rather than an unlink-before-bind — the idiom that, under
// non-recurring names, would be a hijack rather than housekeeping.
//
// The test is a REFUSED CONNECT, and the word is doing work. A bound path with
// no listener behind it is the kernel's own definition of refused
// (`ECONNREFUSED`), which is exactly the crashed-host case. "Did not reply" is
// the wrong test: a wedged extension host is still listening and its own
// window's rows are still valid, so a liveness probe that waited for an answer
// would delete a live peer's socket and reintroduce from the other side the
// very failure unique names exist to prevent.
//
// The sweep lives here rather than in Modaliser because it needs a directory
// listing, which Node has and Modaliser's portable Scheme tree does not.

import * as fs from "node:fs";
import * as net from "node:net";
import * as path from "node:path";
import { POINTER_NAME, SOCKET_SUFFIX } from "./paths";

export interface SweepDeps {
  /** The names in DIR, or an empty list if it cannot be read. */
  readdir(dir: string): string[];
  /** Resolves true if a connect to PATH was REFUSED — nothing is listening. */
  connectRefused(socketPath: string): Promise<boolean>;
  unlink(socketPath: string): void;
  log(message: string): void;
}

export function realSweepDeps(log: (message: string) => void): SweepDeps {
  return {
    readdir: (dir) => {
      try {
        return fs.readdirSync(dir);
      } catch {
        return [];
      }
    },
    connectRefused: (socketPath) =>
      new Promise<boolean>((resolve) => {
        const socket = net.connect(socketPath);
        const settle = (refused: boolean) => {
          socket.removeAllListeners();
          socket.destroy();
          resolve(refused);
        };
        socket.once("connect", () => settle(false));
        socket.once("error", (error: NodeJS.ErrnoException) => {
          // ECONNREFUSED: bound, nothing listening — a dead host's leftover.
          // ENOENT: already gone, so there is nothing to remove either.
          // Anything else (EACCES, EMFILE, …) says something about US rather
          // than about the peer, and must not cost another window its socket.
          settle(error.code === "ECONNREFUSED");
        });
      }),
    unlink: (socketPath) => fs.unlinkSync(socketPath),
    log,
  };
}

/** Remove every socket in DIR whose connect is refused, except SELF. Returns
 *  the paths removed, so a test asserts the decision rather than the
 *  filesystem. */
export async function sweepRefusedSockets(
  dir: string,
  self: string,
  deps: SweepDeps,
): Promise<string[]> {
  const removed: string[] = [];
  for (const name of deps.readdir(dir)) {
    if (name === POINTER_NAME || !name.endsWith(SOCKET_SUFFIX)) {
      continue;
    }
    const candidate = path.join(dir, name);
    if (candidate === self) {
      continue;
    }
    if (!(await deps.connectRefused(candidate))) {
      continue;
    }
    try {
      deps.unlink(candidate);
      removed.push(candidate);
      deps.log(`swept a refused socket: ${candidate}`);
    } catch (error) {
      deps.log(`could not sweep ${candidate}: ${String(error)}`);
    }
  }
  return removed;
}
