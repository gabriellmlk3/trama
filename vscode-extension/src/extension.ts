import * as fs from "fs";
import * as vscode from "vscode";
import * as cli from "./cli";
import { Store } from "./store";
import { CapsuleNode, CapsuleView, FindingsView, TramaNode, TramasView } from "./views";
import { Finding, LiveTrama, TramaState } from "./types";

export function activate(context: vscode.ExtensionContext) {
  const store = new Store();
  const status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 50);
  status.command = "trama.openTrama";
  context.subscriptions.push(store, status);

  const renderStatus = () => {
    const current = store.current;
    if (!current) return status.hide();
    const waiting = store.waitingCount;
    status.text = `$(git-branch) ${current.titulo}` + (waiting ? ` · $(bell) ${waiting}` : "");
    status.tooltip = `${current.branch} · clique para trocar de trama`;
    status.backgroundColor = waiting ? new vscode.ThemeColor("statusBarItem.warningBackground") : undefined;
    status.show();
  };
  store.onDidChange(renderStatus);

  context.subscriptions.push(
    vscode.window.createTreeView("trama.tramas", { treeDataProvider: new TramasView(store) }),
    vscode.window.createTreeView("trama.capsule", { treeDataProvider: new CapsuleView(store) }),
    vscode.window.createTreeView("trama.findings", { treeDataProvider: new FindingsView(store) }),
  );

  const guard = <A extends unknown[]>(fn: (...args: A) => Promise<void> | void) => async (...args: A) => {
    try {
      await fn(...args);
    } catch (e) {
      void vscode.window.showErrorMessage(`Trama: ${(e as Error).message}`);
    }
  };

  const pickTrama = async (title: string, only?: (t: LiveTrama) => boolean): Promise<LiveTrama | undefined> => {
    const list = store.tramas.filter(only ?? (() => true));
    if (!list.length) {
      void vscode.window.showInformationMessage("Nenhuma trama disponível.");
      return undefined;
    }
    const picked = await vscode.window.showQuickPick(
      list.map((t) => ({
        label: t.titulo,
        description: [t.tarefa, t.branch, t.estado === TramaState.parked ? "estacionada" : ""].filter(Boolean).join(" · "),
        detail: t.status.map((s) => s.alias || s.repo).join(" · "),
        trama: t,
      })),
      { title, matchOnDescription: true, matchOnDetail: true },
    );
    return picked?.trama;
  };

  const target = async (node?: TramaNode): Promise<LiveTrama | undefined> =>
    node && node.kind !== "message" ? node.trama : store.current ?? pickTrama("Qual trama?");

  const mutate = async (args: string[], message?: string) => {
    await cli.run(args);
    if (message) void vscode.window.showInformationMessage(message);
    await store.refresh(true);
  };

  const ask = (prompt: string) => vscode.window.showInputBox({ prompt, ignoreFocusOut: true });

  const command = (id: string, fn: (...args: any[]) => Promise<void> | void) =>
    context.subscriptions.push(vscode.commands.registerCommand(id, guard(fn)));

  command("trama.refresh", () => store.refresh(true));

  command("trama.openTrama", async (node?: TramaNode) => {
    const t = node && node.kind === "trama" ? node.trama : await pickTrama("Abrir trama");
    if (!t) return;
    const file = (await cli.run(["vscode", t.slug])).trim();
    const forceNewWindow = vscode.workspace.getConfiguration("trama").get<boolean>("openInNewWindow", true);
    await vscode.commands.executeCommand("vscode.openFolder", vscode.Uri.file(file), { forceNewWindow });
  });

  command("trama.openRepo", async (node: TramaNode) => {
    if (node.kind !== "repo" || !node.status.exists) return;
    const uri = vscode.Uri.file(node.status.path);
    const inside = vscode.workspace.workspaceFolders?.some((f) => f.uri.fsPath === uri.fsPath);
    if (inside) await vscode.commands.executeCommand("revealInExplorer", uri);
    else await vscode.commands.executeCommand("vscode.openFolder", uri, { forceNewWindow: true });
  });

  command("trama.openCapsule", async (node?: TramaNode) => {
    const t = await target(node);
    if (!t) return;
    if (!fs.existsSync(t.capsula)) throw new Error(`a cápsula de ${t.slug} ainda não existe`);
    await vscode.window.showTextDocument(vscode.Uri.file(t.capsula), { preview: false });
  });

  const writer = (id: string, verb: string, prompt: string) =>
    command(id, async () => {
      const t = await target();
      const text = t && (await ask(prompt));
      if (t && text) await mutate([verb, text, "--trama", t.slug]);
    });
  writer("trama.addNote", "nota", "Nota para o diário da trama");
  writer("trama.addDecision", "decisao", "Decisão tomada");
  writer("trama.addPending", "pendencia", "Nova pendência");

  command("trama.completePending", async (node: CapsuleNode) => {
    const t = store.current;
    if (!t || node.kind !== "item") return;
    await mutate(["feito", String(node.item.index), "--trama", t.slug]);
  });

  command("trama.handoff", async () => {
    const t = await target();
    if (!t) return;
    const repo = await vscode.window.showQuickPick(
      t.status.map((s) => ({ label: s.alias || s.repo, description: s.label, value: s.repo })),
      { title: "Passar trabalho para qual repositório?" },
    );
    const text = repo && (await ask(`O que o agente de ${repo.label} precisa saber?`));
    if (repo && text) await mutate(["handoff", repo.value, text, "--trama", t.slug], `Handoff enviado para ${repo.label}`);
  });

  command("trama.park", async (node?: TramaNode) => {
    const t = await target(node);
    if (t) await mutate(["estacionar", t.slug], `${t.titulo} estacionada`);
  });

  command("trama.resume", async (node?: TramaNode) => {
    const t = node ? await target(node) : await pickTrama("Retomar trama", (x) => x.estado === TramaState.parked);
    if (t) await mutate(["retomar", t.slug], `${t.titulo} retomada`);
  });

  command("trama.openPullRequests", async (node?: TramaNode) => {
    const t = await target(node);
    if (!t) return;
    const choice = await vscode.window.showWarningMessage(
      `Abrir os PRs de “${t.titulo}” nos ${t.repos.length} repositórios?`,
      { modal: true, detail: "Simular mostra o plano sem criar nada." },
      "Abrir PRs",
      "Simular",
    );
    if (!choice) return;
    const terminal = vscode.window.createTerminal({ name: `PRs · ${t.titulo}`, cwd: t.caminho });
    terminal.show();
    const exe = `'${cli.executable().replace(/'/g, "'\\''")}'`;
    terminal.sendText(`${exe} pr --trama '${t.slug}'${choice === "Simular" ? " --simular" : ""}`, true);
  });

  command("trama.copyCommand", async (finding: Finding) => {
    if (!finding.command) return;
    await vscode.env.clipboard.writeText(finding.command);
    void vscode.window.showInformationMessage("Comando copiado.");
  });

  renderStatus();
}

export function deactivate() {}
