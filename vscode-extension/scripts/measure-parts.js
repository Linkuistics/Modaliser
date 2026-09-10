#!/usr/bin/env node
// Measure the `parts` round-trip against a live peer.
//
// Committed, and that is the point. The cost conclusion in an earlier design
// session had to be withdrawn because its instrument was a standalone binary
// nobody kept, so the number could not be re-run and therefore could not be
// trusted (docs/specs/vscode-window-parts.md, decision 9). This is the
// re-runnable half of the answer; the other half is `(modaliser instrument)`'s
// `vscode-wire` / `vscode-parse` spans in `(modaliser apps vscode)`, which
// attribute the same round-trip *inside a leader press* once a panel is bound
// to it (docs/how-to/measure-a-leader-press.md).
//
// What this measures is the peer's whole service time as seen from outside —
// connect, request, the extension host's event loop scheduling the callback,
// building the reply, and the write back. That event loop is shared with every
// other extension in the window, which is exactly why the budget is set
// against the wedged case rather than this number.
//
//   node scripts/measure-parts.js [iterations]
//
// With no socket named it measures every peer in the socket directory.

const fs = require("node:fs");
const net = require("node:net");
const os = require("node:os");
const path = require("node:path");

const DIR = path.join(os.homedir(), ".config", "modaliser", "vscode");
const LINE = JSON.stringify({ id: "modaliser", method: "parts", params: {} }) + "\n";

function once(socketPath) {
  return new Promise((resolve) => {
    const started = process.hrtime.bigint();
    const socket = net.connect(socketPath);
    let buffer = "";
    socket.setEncoding("utf8");
    socket.on("connect", () => socket.write(LINE));
    socket.on("data", (chunk) => {
      buffer += chunk;
      const newline = buffer.indexOf("\n");
      if (newline >= 0) {
        socket.destroy();
        resolve({ ms: Number(process.hrtime.bigint() - started) / 1e6, bytes: newline });
      }
    });
    socket.on("error", (error) => {
      socket.destroy();
      resolve({ error: error.code });
    });
  });
}

async function measure(socketPath, iterations) {
  const times = [];
  let bytes = 0;
  let error;
  for (let i = 0; i < iterations; i++) {
    const run = await once(socketPath);
    if (run.error) {
      error = run.error;
      break;
    }
    times.push(run.ms);
    bytes = run.bytes;
  }
  const name = path.basename(socketPath);
  if (error || times.length === 0) {
    console.log(`${name}  unreachable (${error ?? "no reply"})`);
    return;
  }
  times.sort((a, b) => a - b);
  const at = (q) => times[Math.min(times.length - 1, Math.floor(q * times.length))].toFixed(3);
  console.log(
    `${name}  n=${times.length} reply=${bytes}B  ` +
      `min=${at(0)} p50=${at(0.5)} p95=${at(0.95)} max=${times[times.length - 1].toFixed(3)} ms`,
  );
}

async function main() {
  const args = process.argv.slice(2);
  const named = args.filter((a) => a.endsWith(".sock"));
  const iterations = Number(args.find((a) => /^\d+$/.test(a)) ?? 200);
  const sockets =
    named.length > 0
      ? named
      : fs
          .readdirSync(DIR)
          .filter((n) => n.endsWith(".sock"))
          .map((n) => path.join(DIR, n));
  if (sockets.length === 0) {
    console.error(`no peers in ${DIR} — is the extension installed and VSCode running?`);
    process.exitCode = 1;
    return;
  }
  for (const socketPath of sockets) {
    await measure(socketPath, iterations);
  }
}

void main();
