import * as vscode from "vscode";
import * as cli from "./cli";
import { Capsule, Finding, LiveTrama, OverallState, AgentState, TramaState } from "./types";

const FINDINGS_MAX_AGE_MS = 120_000;

export class Store implements vscode.Disposable {
  private readonly emitter = new vscode.EventEmitter<void>();
  readonly onDidChange = this.emitter.event;
  private timer: NodeJS.Timeout | undefined;
  private findingsLoadedAt = 0;
  private busy = false;

  state: OverallState | undefined;
  capsule: Capsule | undefined;
  findings: Finding[] = [];
  error: string | undefined;

  constructor() {
    this.schedule();
    vscode.workspace.onDidChangeConfiguration((e) => {
      if (e.affectsConfiguration("trama")) {
        this.schedule();
        void this.refresh(true);
      }
    });
    vscode.workspace.onDidChangeWorkspaceFolders(() => void this.refresh());
    void this.refresh(true);
  }

  private schedule() {
    if (this.timer) clearInterval(this.timer);
    const seconds = vscode.workspace.getConfiguration("trama").get<number>("refreshSeconds", 20);
    this.timer = setInterval(() => void this.refresh(), Math.max(5, seconds) * 1000);
  }

  get tramas(): LiveTrama[] {
    return (this.state?.tramas ?? []).filter((t) => t.estado !== TramaState.archived);
  }

  get current(): LiveTrama | undefined {
    const folders = vscode.workspace.workspaceFolders?.map((f) => f.uri.fsPath) ?? [];
    return this.tramas.find((t) => folders.some((f) => f === t.caminho || f.startsWith(t.caminho + "/")));
  }

  get waitingCount(): number {
    const slug = this.current?.slug;
    return (this.state?.agents ?? []).filter((a) => a.trama === slug && a.estado === AgentState.waiting).length;
  }

  async refresh(withFindings = false) {
    if (this.busy) return;
    this.busy = true;
    try {
      this.state = await cli.json<OverallState>(["estado"]);
      this.error = undefined;
      const current = this.current;
      this.capsule = current ? await cli.json<Capsule>(["capsula", current.slug]).catch(() => undefined) : undefined;
      await vscode.commands.executeCommand("setContext", "trama.inTrama", current !== undefined);
      if (withFindings || Date.now() - this.findingsLoadedAt > FINDINGS_MAX_AGE_MS) await this.loadFindings();
    } catch (e) {
      this.error = (e as Error).message;
    } finally {
      this.busy = false;
      this.emitter.fire();
    }
  }

  private async loadFindings() {
    try {
      this.findings = await cli.json<Finding[]>(["achados"]);
      this.findingsLoadedAt = Date.now();
    } catch {
      this.findings = [];
    }
  }

  dispose() {
    if (this.timer) clearInterval(this.timer);
    this.emitter.dispose();
  }
}
