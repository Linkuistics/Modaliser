// The transport end to end, over a real AF_UNIX socket — but with the API
// surface still faked, so this exercises the framing and the silence, not
// VSCode.

import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as net from "node:net";
import * as os from "node:os";
import * as path from "node:path";
import { after, describe, it } from "node:test";

import { buildParts } from "../src/parts";
import { TokenRegistry } from "../src/registry";
import { createServer } from "../src/server";
import { FakeEnv, textTab } from "./fakes";

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "modaliser-server-"));
after(() => fs.rmSync(dir, { recursive: true, force: true }));

let n = 0;
async function listening(env: FakeEnv, registry: TokenRegistry) {
  const socketPath = path.join(dir, `s${n++}.sock`);
  const server = createServer(env, registry);
  await new Promise<void>((resolve) => server.listen(socketPath, resolve));
  return {
    socketPath,
    close: () => new Promise<void>((resolve) => server.close(() => resolve())),
  };
}

/** Modaliser's `unix-socket-request`: one line out, one line back. */
function request(socketPath: string, line: string, timeoutMs = 2000): Promise<string | null> {
  return new Promise((resolve) => {
    const socket = net.connect(socketPath);
    let buffer = "";
    const done = (value: string | null) => {
      socket.removeAllListeners();
      socket.destroy();
      resolve(value);
    };
    const timer = setTimeout(() => done(null), timeoutMs);
    socket.setEncoding("utf8");
    socket.on("connect", () => socket.write(`${line}\n`));
    socket.on("data", (chunk: string) => {
      buffer += chunk;
      const newline = buffer.indexOf("\n");
      if (newline >= 0) {
        clearTimeout(timer);
        done(buffer.slice(0, newline));
      }
    });
    socket.on("close", () => {
      clearTimeout(timer);
      done(buffer.length > 0 ? buffer : null);
    });
    socket.on("error", () => {
      clearTimeout(timer);
      done(null);
    });
  });
}

/** Modaliser's `unix-socket-send`: write, close, never read. */
function send(socketPath: string, line: string): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = net.connect(socketPath);
    socket.on("connect", () => socket.end(`${line}\n`, () => resolve(true)));
    socket.on("error", () => resolve(false));
  });
}

describe("the socket server", () => {
  it("answers one parts request per connection, newline framed", async () => {
    const env = new FakeEnv();
    env.terminal("zsh", "/p");
    env.group(1).add(textTab("fsm.sld", "/p/fsm.sld"));
    const peer = await listening(env, new TokenRegistry());
    env.peer = peer.socketPath;

    const reply = await request(peer.socketPath, JSON.stringify({ id: 1, method: "parts", params: {} }));
    assert.ok(reply !== null);
    const parsed = JSON.parse(reply!) as { id: number; result: { peer: string } };
    assert.equal(parsed.id, 1);
    assert.equal(parsed.result.peer, peer.socketPath);
    await peer.close();
  });

  it("puts nothing on the wire for a notification", async () => {
    const env = new FakeEnv();
    const zsh = env.terminal("zsh");
    const registry = new TokenRegistry();
    const peer = await listening(env, registry);
    const token = buildParts(env, registry).terminals[0]!.token;

    // Read the connection to EOF rather than sending-and-forgetting, so the
    // assertion is "the peer wrote no bytes" rather than "we did not look".
    const reply = await request(
      peer.socketPath,
      JSON.stringify({ id: 2, method: "focus-terminal", params: { token } }),
    );
    assert.equal(reply, null);
    assert.equal(zsh.shown, 1);
    await peer.close();
  });

  it("survives a caller that closed before the notification was handled", async () => {
    const env = new FakeEnv();
    const zsh = env.terminal("zsh");
    const registry = new TokenRegistry();
    const peer = await listening(env, registry);
    const token = buildParts(env, registry).terminals[0]!.token;

    assert.equal(
      await send(peer.socketPath, JSON.stringify({ id: 3, method: "focus-terminal", params: { token } })),
      true,
    );
    // Abandoning the reply does not abandon the request: the bytes are in the
    // peer's receive buffer before close, and AF_UNIX stream delivery
    // guarantees the peer reads them before seeing EOF.
    await new Promise((resolve) => setTimeout(resolve, 50));
    assert.equal(zsh.shown, 1);
    await peer.close();
  });

  it("does not fall over on a garbage line", async () => {
    const env = new FakeEnv();
    const peer = await listening(env, new TokenRegistry());
    assert.equal(await request(peer.socketPath, "}{"), null);

    // Still serving.
    const reply = await request(peer.socketPath, JSON.stringify({ id: 4, method: "parts", params: {} }));
    assert.ok(reply !== null);
    await peer.close();
  });
});
