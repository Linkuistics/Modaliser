// The socket name, the directory, and the pointer file.

import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { describe, it } from "node:test";

import {
  allocateSocketPath,
  ensureSocketDir,
  pointerPath,
  socketDir,
  socketFileName,
} from "../src/paths";
import { realPointerFs, writePointer } from "../src/pointer";

function tempDir(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), "modaliser-companion-"));
}

describe("the socket directory", () => {
  it("is Modaliser's own config root, which SchemeEngine also hard-codes", () => {
    // Not XDG_CONFIG_HOME: Modaliser's Swift side does not honour it, so
    // honouring it here would put the two halves in different directories.
    assert.equal(
      socketDir({ HOME: "/Users/someone", XDG_CONFIG_HOME: "/elsewhere" }),
      "/Users/someone/.config/modaliser/vscode",
    );
  });

  it("leaves a bound path well inside sun_path's 104 bytes", () => {
    const name = socketFileName(Date.now(), 99999, "zzzzzz");
    const full = path.join(socketDir({ HOME: "/Users/someone" }), name);
    assert.ok(Buffer.byteLength(full) < 104, `${full} is ${Buffer.byteLength(full)} bytes`);
  });

  it("is created 0700, even when it already exists with looser bits", () => {
    const root = tempDir();
    const dir = path.join(root, "vscode");
    fs.mkdirSync(dir, { mode: 0o755 });
    fs.chmodSync(dir, 0o755);

    ensureSocketDir(dir);

    // `mkdir`'s mode argument is subject to the umask and does nothing at all
    // for a directory that already exists, so the chmod is what decides.
    assert.equal(fs.statSync(dir).mode & 0o777, 0o700);
    fs.rmSync(root, { recursive: true, force: true });
  });
});

describe("the socket name", () => {
  it("cannot be minted again by a later instance", () => {
    const earlier = socketFileName(1_700_000_000_000, 4321, "aaa");
    const later = socketFileName(1_700_000_000_001, 4321, "aaa");
    // The monotonic component is what makes this a guarantee rather than a
    // birthday problem: a target is a socket path plus a token, so a path
    // back in service under a new instance would be an address that outlived
    // what it addressed (ADR-0027).
    assert.notEqual(earlier, later);
  });

  it("separates two windows started in the same millisecond", () => {
    assert.notEqual(
      socketFileName(1_700_000_000_000, 111, "aaa"),
      socketFileName(1_700_000_000_000, 222, "aaa"),
    );
  });

  it("refuses to return a name that already exists", () => {
    const taken = new Set<string>();
    let clock = 1_700_000_000_000;
    const deps = {
      now: () => clock++,
      pid: () => 4321,
      randomSuffix: () => "aaa",
      exists: (candidate: string) => taken.has(candidate),
    };
    const first = allocateSocketPath("/d", deps);
    taken.add(first);
    const second = allocateSocketPath("/d", deps);

    // Never bind over an existing name: under non-recurring names the tidy
    // unlink-then-bind idiom is a HIJACK — a second instance unlinks a live
    // peer's socket, the first keeps listening on an unreachable inode, and
    // the path now resolves to a different token space.
    assert.notEqual(second, first);
  });

  it("gives up rather than guessing forever", () => {
    const deps = {
      now: () => 1,
      pid: () => 1,
      randomSuffix: () => "same",
      exists: () => true,
    };
    assert.throws(() => allocateSocketPath("/d", deps, 3), /could not find an unused socket name/);
  });
});

describe("the pointer file", () => {
  it("names this instance's socket", () => {
    const dir = tempDir();
    writePointer(dir, "/s/vs-abc.sock", 42, realPointerFs());
    assert.equal(fs.readFileSync(pointerPath(dir), "utf8").trim(), "/s/vs-abc.sock");
    fs.rmSync(dir, { recursive: true, force: true });
  });

  it("replaces the previous window's claim atomically", () => {
    const dir = tempDir();
    const seen: string[] = [];
    const io = {
      writeFileSync: (file: string, data: string) => {
        seen.push(`write ${path.basename(file)}`);
        fs.writeFileSync(file, data);
      },
      renameSync: (from: string, to: string) => {
        seen.push(`rename ${path.basename(from)} -> ${path.basename(to)}`);
        fs.renameSync(from, to);
      },
      unlinkSync: (file: string) => fs.unlinkSync(file),
    };

    writePointer(dir, "/s/one.sock", 1, io);
    writePointer(dir, "/s/two.sock", 2, io);

    // A reader is a plain `read-file-text` with no locking, so the target is
    // never opened for writing: a concurrent read sees the old path or the
    // new one, never a truncated one.
    assert.deepEqual(seen, [
      "write focused.1.tmp",
      "rename focused.1.tmp -> focused",
      "write focused.2.tmp",
      "rename focused.2.tmp -> focused",
    ]);
    assert.equal(fs.readFileSync(pointerPath(dir), "utf8").trim(), "/s/two.sock");
    assert.deepEqual(fs.readdirSync(dir), ["focused"]);
    fs.rmSync(dir, { recursive: true, force: true });
  });
});
