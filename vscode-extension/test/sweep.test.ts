// The activation sweep: refused, not unanswered.

import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as net from "node:net";
import * as os from "node:os";
import * as path from "node:path";
import { describe, it } from "node:test";

import { realSweepDeps, sweepRefusedSockets, type SweepDeps } from "../src/sweep";

function deps(
  names: string[],
  refused: (p: string) => boolean,
  removed: string[],
): SweepDeps {
  return {
    readdir: () => names,
    connectRefused: async (p) => refused(p),
    unlink: (p) => {
      removed.push(p);
    },
    log: () => {},
  };
}

describe("the sweep", () => {
  it("removes a socket whose connect is refused", async () => {
    const removed: string[] = [];
    const swept = await sweepRefusedSockets(
      "/d",
      "/d/mine.sock",
      deps(["dead.sock", "mine.sock"], () => true, removed),
    );
    assert.deepEqual(swept, ["/d/dead.sock"]);
    assert.deepEqual(removed, ["/d/dead.sock"]);
  });

  it("leaves a socket that answers, and a wedged one that merely listens", async () => {
    const removed: string[] = [];
    // The test is REFUSED, not "did not reply": a wedged extension host is
    // still listening and its own window's rows are still valid, so a
    // liveness probe that waited for an answer would delete a live peer's
    // socket — reintroducing from the other side the hijack that unique
    // names exist to prevent.
    const swept = await sweepRefusedSockets(
      "/d",
      "/d/mine.sock",
      deps(["busy.sock", "mine.sock"], () => false, removed),
    );
    assert.deepEqual(swept, []);
    assert.deepEqual(removed, []);
  });

  it("never touches its own socket or the pointer file", async () => {
    const removed: string[] = [];
    await sweepRefusedSockets(
      "/d",
      "/d/mine.sock",
      deps(["mine.sock", "focused", "focused.42.tmp", "notes.txt"], () => true, removed),
    );
    assert.deepEqual(removed, []);
  });

  it("distinguishes a refused connect from a live one against the kernel", async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "modaliser-sweep-"));
    const live = path.join(dir, "live.sock");
    const dead = path.join(dir, "dead.sock");
    const inert = path.join(dir, "inert.sock");

    const server = net.createServer(() => {});
    await new Promise<void>((resolve) => server.listen(live, resolve));

    // A crashed host's leftover has to be produced the way a crash produces
    // one — a process that bound the path and was killed without running its
    // cleanup. An in-process `server.close()` will not do: Node unlinks on
    // close, and a hand-written regular file in its place is not a socket at
    // all, so a connect to it fails ENOTSOCK rather than ECONNREFUSED. That
    // difference is the whole subject of this test.
    const child = spawn(process.execPath, [
      "-e",
      `require('node:net').createServer(()=>{}).listen(${JSON.stringify(dead)},()=>console.log('up'))`,
    ]);
    await new Promise<void>((resolve) => child.stdout.once("data", () => resolve()));
    child.kill("SIGKILL");
    await new Promise<void>((resolve) => child.once("exit", () => resolve()));
    assert.ok(fs.existsSync(dead), "the killed peer should have left its socket behind");

    // And something in the directory that is not a socket at all: an
    // unrecognised failure says something about US, not about a peer, and
    // must not cost anybody a file.
    fs.writeFileSync(inert, "");

    const removed = await sweepRefusedSockets(dir, live, realSweepDeps(() => {}));

    assert.deepEqual(removed, [dead]);
    assert.ok(fs.existsSync(live));
    assert.ok(fs.existsSync(inert));
    await new Promise<void>((resolve) => server.close(() => resolve()));
    fs.rmSync(dir, { recursive: true, force: true });
  });
});
