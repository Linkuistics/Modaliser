// The activation wiring, and the ONE place in this extension that imports the
// `vscode` module at runtime.
//
// Everything with behaviour in it lives behind `PeerEnv` and is tested against
// fakes; this file is the adapter that binds those accessors to the real
// namespace, plus the lifecycle. Keeping the adapter thin is what makes the
// tests worth anything, so resist putting a decision here — if a branch wants
// to exist in this file, it probably belongs in a module that has a test.
//
// Two facts about the host, both load-bearing and both declared in
// package.json rather than here:
//
//   extensionKind: ["ui"] — a window connected to SSH, a container or WSL
//   would otherwise run this on the remote, where its socket is on the wrong
//   machine.
//
//   onStartupFinished — the socket must exist from window start. Activating
//   lazily is a deadlock in slow motion: the only thing that would activate
//   this extension is a request arriving on the socket, and the socket does
//   not exist until it activates.

import * as fs from "node:fs";
import * as net from "node:net";
import * as vscode from "vscode";

import type { PeerEnv, TabGroupLike, TerminalLike } from "./peerEnv";
import {
  allocateSocketPath,
  ensureSocketDir,
  realAllocateDeps,
  socketDir,
} from "./paths";
import { installPointerClaim } from "./focusPointer";
import { realPointerFs, writePointer } from "./pointer";
import { TokenRegistry } from "./registry";
import { createServer } from "./server";
import { realSweepDeps, sweepRefusedSockets } from "./sweep";
import { classifyTabInput } from "./tabKind";

let server: net.Server | undefined;
let boundSocketPath: string | undefined;

function makeEnv(peer: string, log: (message: string) => void): PeerEnv {
  return {
    peer,
    focused: () => vscode.window.state.focused,
    terminals: () =>
      vscode.window.terminals as unknown as readonly TerminalLike[],
    tabGroups: () =>
      vscode.window.tabGroups.all as unknown as readonly TabGroupLike[],
    activeTabGroup: () => vscode.window.tabGroups.activeTabGroup as unknown as TabGroupLike,
    // Shipped VSCode 1.136.2: focusNextGroup traverses existing groups only;
    // openEditorAtIndex takes a zero-based index in the active group and
    // passes that existing EditorInput to editorService.openEditor.
    // src/vs/workbench/browser/parts/editor/{editorActions,editorCommands}.ts
    focusNextGroup: () =>
      Promise.resolve(vscode.commands.executeCommand("workbench.action.focusNextGroup")),
    openEditorAtIndex: (index) =>
      Promise.resolve(vscode.commands.executeCommand("workbench.action.openEditorAtIndex", index)),
    activeTerminal: () =>
      vscode.window.activeTerminal as unknown as TerminalLike | undefined,
    workspace: () => vscode.workspace.workspaceFolders?.[0]?.uri.fsPath ?? null,
    // The classifier is handed the real namespace here and fakes in the
    // tests; see tabKind.ts for why the table is injected rather than
    // imported.
    classify: (input) => classifyTabInput(vscode, input),
    // Metadata and definite absence: VSCode 1.136.0 FileSystem/FileSystemError.
    // https://github.com/microsoft/vscode/blob/1.136.0/src/vscode-dts/vscode.d.ts#L8871-L8919
    statResource: (uri) => Promise.resolve(vscode.workspace.fs.stat(uri as vscode.Uri)),
    isFileNotFound: (error) =>
      error instanceof vscode.FileSystemError && error.code === "FileNotFound",
    // https://github.com/microsoft/vscode/blob/1.136.0/src/vscode-dts/vscode.d.ts#L18133-L18142
    closeTab: (tab, preserveFocus) =>
      Promise.resolve(vscode.window.tabGroups.close(tab as vscode.Tab, preserveFocus)),
    showTextDocument: (uri, options) =>
      Promise.resolve(
        vscode.window.showTextDocument(uri as vscode.Uri, {
          viewColumn: options.viewColumn as vscode.ViewColumn,
          preview: options.preview,
        }),
      ),
    openNotebookDocument: (uri) =>
      Promise.resolve(vscode.workspace.openNotebookDocument(uri as vscode.Uri)),
    // Custom-editor activation. Read out of the shipped registration:
    // `vscode.openWith(resource, viewId, columnOrOptions)` takes the same
    // `TextDocumentShowOptions` object `showTextDocument` does.
    openWith: (uri, viewType, options) =>
      Promise.resolve(
        vscode.commands.executeCommand("vscode.openWith", uri, viewType, {
          viewColumn: options.viewColumn as vscode.ViewColumn,
          preview: options.preview,
        }),
      ),
    showNotebookDocument: (document, options) =>
      Promise.resolve(
        vscode.window.showNotebookDocument(
          document as vscode.NotebookDocument,
          { viewColumn: options.viewColumn as vscode.ViewColumn },
        ),
      ),
    log,
  };
}

export function activate(context: vscode.ExtensionContext): void {
  const output = vscode.window.createOutputChannel("Modaliser Companion");
  context.subscriptions.push(output);
  const log = (message: string) => output.appendLine(message);

  const dir = socketDir(process.env);
  try {
    ensureSocketDir(dir);
  } catch (error) {
    log(`could not create ${dir}: ${String(error)} — this window has no peer`);
    return;
  }

  let socketPath: string;
  try {
    socketPath = allocateSocketPath(dir, realAllocateDeps());
  } catch (error) {
    log(`${String(error)} — this window has no peer`);
    return;
  }

  const registry = new TokenRegistry();
  const env = makeEnv(socketPath, log);
  const listener = createServer(env, registry);
  server = listener;
  boundSocketPath = socketPath;

  listener.listen(socketPath, () => {
    log(`listening on ${socketPath}`);
    // The sweep runs after this instance has bound, so its own path is
    // already in the directory and is skipped by name rather than by luck.
    void sweepRefusedSockets(dir, socketPath, realSweepDeps(log));
  });

  const claimPointer = () => {
    try {
      writePointer(dir, socketPath, process.pid, realPointerFs());
    } catch (error) {
      log(`could not write the focus pointer: ${String(error)}`);
    }
  };

  // Both halves of the claim policy — at activation and on a focus gain —
  // live in `focusPointer.ts`, where a test can reach them. See its header
  // for why each is a silent defect if omitted.
  context.subscriptions.push(
    installPointerClaim({
      focusedNow: () => vscode.window.state.focused,
      onWindowState: (handler) =>
        vscode.window.onDidChangeWindowState((state) => handler(state.focused)),
      claim: claimPointer,
    }),
  );

  context.subscriptions.push({ dispose: () => teardown(log) });
}

export function deactivate(): void {
  teardown(() => {
    /* the output channel is disposed by now; failures here are unreportable */
  });
}

function teardown(log: (message: string) => void): void {
  const listener = server;
  const socketPath = boundSocketPath;
  server = undefined;
  boundSocketPath = undefined;
  if (listener !== undefined) {
    try {
      listener.close();
    } catch (error) {
      log(`could not close the socket server: ${String(error)}`);
    }
  }
  if (socketPath !== undefined) {
    // Unlink our own, and only our own. The pointer file is deliberately left
    // alone: it may name another window by now, and a departing peer that
    // cleared it would blank a listing that has nothing to do with it.
    try {
      fs.unlinkSync(socketPath);
    } catch {
      // Already gone — a sweep from another instance, or the directory
      // removed under us. Either way there is nothing left to do.
    }
  }
}
