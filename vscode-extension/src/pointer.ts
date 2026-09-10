// The last-focused pointer file (docs/specs/vscode-window-parts.md,
// decision 3; ADR-0027).
//
// One small piece of shared mutable state, written by whichever window last
// took focus and outliving the process that wrote it. Modaliser consults it to
// START a read and never consults it again — every action goes to the `peer`
// path the reply itself carried — so a pointer that moves between the read and
// the press cannot redirect an action.
//
// WRITTEN ATOMICALLY, because a reader is a plain `read-file-text` with no
// locking: write a sibling temp file, then rename over the target. `rename`
// within one directory is atomic, so a concurrent reader sees either the old
// path or the new one and never a truncated one.
//
// AND WRITTEN AT ACTIVATION TOO, not only from the event.
// `onDidChangeWindowState` is declared to fire when the state CHANGES, so a
// window that is already focused when `onStartupFinished` runs has nothing to
// change and a subscription-only design never writes a pointer for it. That is
// not an edge case — it is the ordinary single-window case, every window after
// an extension-host restart, and the first run after installing — and its
// symptom is two empty panels until the human clicks away and back, with no
// error anywhere. `extension.ts` does both halves; this module does the write.

import * as fs from "node:fs";
import { pointerPath } from "./paths";

export interface PointerFs {
  writeFileSync(file: string, data: string, options: { mode: number }): void;
  renameSync(from: string, to: string): void;
  unlinkSync(file: string): void;
}

export function realPointerFs(): PointerFs {
  return {
    writeFileSync: (file, data, options) => fs.writeFileSync(file, data, options),
    renameSync: (from, to) => fs.renameSync(from, to),
    unlinkSync: (file) => fs.unlinkSync(file),
  };
}

/** Replace the pointer in DIR with SOCKETPATH. The temp name carries the pid
 *  so two windows racing to claim focus cannot collide on it. */
export function writePointer(
  dir: string,
  socketPath: string,
  pid: number,
  io: PointerFs,
): void {
  const target = pointerPath(dir);
  const temp = `${target}.${pid}.tmp`;
  try {
    io.writeFileSync(temp, `${socketPath}\n`, { mode: 0o600 });
    io.renameSync(temp, target);
  } catch (error) {
    try {
      io.unlinkSync(temp);
    } catch {
      // The temp file may never have been created; nothing to clean up.
    }
    throw error;
  }
}
