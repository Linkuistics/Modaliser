// Where the sockets and the pointer file live, and the name an instance
// binds (docs/specs/vscode-window-parts.md, decision 3; ADR-0026, ADR-0027).

import * as fs from "node:fs";
import * as path from "node:path";

/** The one filename in the directory that is not a socket. Modaliser reads it
 *  with the `read-file-text` it already has, and dials what it names. */
export const POINTER_NAME = "focused";

/** Modaliser's user config root, which is a fixed `~/.config/modaliser` on
 *  this side too — `SchemeEngine` does not honour `XDG_CONFIG_HOME`, so
 *  honouring it here would put the two halves in different directories.
 *
 *  Short on purpose: a bound AF_UNIX path on macOS must fit `sun_path`'s 104
 *  bytes, and this leaves ~65 of them for the socket name. */
export function socketDir(env: NodeJS.ProcessEnv): string {
  return path.join(env.HOME ?? "", ".config", "modaliser", "vscode");
}

export function pointerPath(dir: string): string {
  return path.join(dir, POINTER_NAME);
}

/** Create the directory 0700 and hold it there. `mkdir`'s mode argument is
 *  subject to the umask and the directory may already exist from an earlier
 *  install, so the `chmod` is the one that actually decides — this is the
 *  whole of what keeps the sockets and the pointer out of another user's
 *  reach (ADR-0026). */
export function ensureSocketDir(dir: string): void {
  fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  fs.chmodSync(dir, 0o700);
}

export const SOCKET_SUFFIX = ".sock";

/** A socket file name that no instance ever reuses.
 *
 *  "Unique" here means CANNOT RECUR, not unlikely-to: a target is a socket
 *  path plus a token, so a path back in service under a new instance is an
 *  address that outlived what it addressed, and the new instance's counter
 *  starts where the old one's did — a row drawn before an extension-host
 *  restart would reach the reloaded window and its token would resolve, to a
 *  different tab. The window keeps focus across such a restart, so every
 *  other guard in this design passes while the wrong tab is activated.
 *
 *  Three ingredients, and the first is the one that matters: `nowMs` is
 *  monotonic across restarts, so a later instance cannot mint an earlier
 *  instance's name however the pid and the random suffix fall. The pid
 *  separates two windows started in the same millisecond; the random suffix
 *  is belt-and-braces against a clock stepped backwards. `allocateSocketPath`
 *  then refuses to return a name that already exists, which is what turns
 *  "improbable" into "checked".
 *
 *  Note what all this rules out: the tidy unlink-a-stale-path-then-bind
 *  idiom, which under recurring names is either dead code or a hijack — a
 *  second instance unlinks a live peer's socket, the first keeps listening on
 *  an unlinked inode nothing can reach, and the path now resolves to a
 *  different token space. The tidy-up here is `sweep.ts` instead. */
export function socketFileName(
  nowMs: number,
  pid: number,
  randomSuffix: string,
): string {
  return `vs-${nowMs.toString(36)}-${pid.toString(36)}-${randomSuffix}${SOCKET_SUFFIX}`;
}

export interface AllocateDeps {
  now(): number;
  pid(): number;
  randomSuffix(): string;
  exists(candidate: string): boolean;
}

/** A path in DIR that nothing has bound. Tries a handful of names and then
 *  gives up loudly rather than binding over something: with a monotonic
 *  component in the name, an existing candidate means the environment is not
 *  what this code believes, and guessing again forever would hide that. */
export function allocateSocketPath(
  dir: string,
  deps: AllocateDeps,
  attempts = 8,
): string {
  for (let i = 0; i < attempts; i++) {
    const candidate = path.join(
      dir,
      socketFileName(deps.now(), deps.pid(), deps.randomSuffix()),
    );
    if (!deps.exists(candidate)) {
      return candidate;
    }
  }
  throw new Error(
    `modaliser-companion: could not find an unused socket name in ${dir} after ${attempts} attempts`,
  );
}

/** The deps `allocateSocketPath` runs with in the extension host. */
export function realAllocateDeps(): AllocateDeps {
  return {
    now: () => Date.now(),
    pid: () => process.pid,
    randomSuffix: () => Math.floor(Math.random() * 0x1000000).toString(36),
    exists: (candidate: string) => fs.existsSync(candidate),
  };
}
