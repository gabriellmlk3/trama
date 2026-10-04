import * as vscode from "vscode";
import { Store } from "./store";
import { AgentState, CapsuleItem, Finding, LiveTrama, RepoStatus, TramaState } from "./types";

const attention = new vscode.ThemeColor("list.warningForeground");
const problem = new vscode.ThemeColor("list.errorForeground");

export type TramaNode = { kind: "trama"; trama: LiveTrama } | { kind: "repo"; trama: LiveTrama; status: RepoStatus } | { kind: "message"; text: string };

export class TramasView implements vscode.TreeDataProvider<TramaNode> {
  private readonly emitter = new vscode.EventEmitter<void>();
  readonly onDidChangeTreeData = this.emitter.event;

  constructor(private readonly store: Store) {
    store.onDidChange(() => this.emitter.fire());
  }

  getChildren(node?: TramaNode): TramaNode[] {
    if (!node) {
      if (this.store.error && !this.store.state) return [{ kind: "message", text: this.store.error }];
      return this.store.tramas.map((trama) => ({ kind: "trama", trama }));
    }
    if (node.kind === "trama") return node.trama.status.map((status) => ({ kind: "repo", trama: node.trama, status }));
    return [];
  }

  getTreeItem(node: TramaNode): vscode.TreeItem {
    if (node.kind === "message") {
      const item = new vscode.TreeItem(node.text);
      item.iconPath = new vscode.ThemeIcon("warning", problem);
      return item;
    }
    return node.kind === "trama" ? this.tramaItem(node.trama) : this.repoItem(node.trama, node.status);
  }

  private tramaItem(t: LiveTrama): vscode.TreeItem {
    const parked = t.estado === TramaState.parked;
    const here = this.store.current?.slug === t.slug;
    const item = new vscode.TreeItem(t.titulo, here ? vscode.TreeItemCollapsibleState.Expanded : vscode.TreeItemCollapsibleState.Collapsed);
    const parts = [t.branch];
    if (t.tarefa) parts.unshift(t.tarefa);
    if (parked) parts.push("estacionada");
    if (here) parts.push("esta janela");
    item.description = parts.join(" · ");
    item.contextValue = parked ? "trama-parked" : "trama";
    item.iconPath = new vscode.ThemeIcon(parked ? "debug-pause" : "git-branch");
    item.tooltip = new vscode.MarkdownString(`**${t.titulo}**\n\n\`${t.branch}\` · ${t.repos.length} repositórios\n\n${t.caminho}`);
    return item;
  }

  private repoItem(t: LiveTrama, s: RepoStatus): vscode.TreeItem {
    const item = new vscode.TreeItem(s.alias || s.repo);
    item.contextValue = "repo";
    if (!s.exists) {
      item.description = s.error ?? "worktree não encontrado";
      item.iconPath = new vscode.ThemeIcon("warning", problem);
      return item;
    }
    const waiting = s.agents.find((a) => a.estado === AgentState.waiting);
    const working = s.agents.find((a) => a.estado === AgentState.working);
    const bits: string[] = [];
    if (s.ahead) bits.push(`↑${s.ahead}`);
    if (s.behind) bits.push(`↓${s.behind}`);
    bits.push(s.changed === 0 ? "limpo" : `${s.changed} ${s.changed === 1 ? "alterado" : "alterados"}`);
    if (s.conflict === "conflito") bits.push(`conflito com ${s.base}`);
    if (waiting) bits.push("agente aguardando");
    else if (working) bits.push("agente trabalhando");
    item.description = bits.join(" · ");
    item.iconPath = s.conflict === "conflito"
      ? new vscode.ThemeIcon("git-merge", problem)
      : waiting
        ? new vscode.ThemeIcon("bell", attention)
        : working
          ? new vscode.ThemeIcon("sync~spin")
          : new vscode.ThemeIcon(s.changed ? "diff-modified" : "check");
    item.tooltip = [s.label, s.branch, waiting?.mensagem].filter(Boolean).join(" · ");
    item.command = { command: "trama.openRepo", title: "Mostrar repositório", arguments: [{ kind: "repo", trama: t, status: s }] };
    return item;
  }

  getParent(node: TramaNode): TramaNode | undefined {
    return node.kind === "repo" ? { kind: "trama", trama: node.trama } : undefined;
  }
}

export type CapsuleNode =
  | { kind: "section"; title: string; items: CapsuleItem[]; icon: string; section: "goal" | "pending" | "handoffs" | "decisions" | "journal" }
  | { kind: "item"; item: CapsuleItem; section: string }
  | { kind: "text"; text: string };

export class CapsuleView implements vscode.TreeDataProvider<CapsuleNode> {
  private readonly emitter = new vscode.EventEmitter<void>();
  readonly onDidChangeTreeData = this.emitter.event;

  constructor(private readonly store: Store) {
    store.onDidChange(() => this.emitter.fire());
  }

  getChildren(node?: CapsuleNode): CapsuleNode[] {
    const c = this.store.capsule;
    if (!node) {
      if (!this.store.current) return [];
      if (!c?.exists) return [{ kind: "text", text: "A cápsula desta trama ainda não existe." }];
      const open = c.pending.filter((p) => !p.done);
      const unread = c.handoffs.filter((h) => !h.done);
      const sections: CapsuleNode[] = [];
      if (c.goal) sections.push({ kind: "section", title: "Objetivo", items: [], icon: "target", section: "goal" });
      sections.push(
        { kind: "section", title: `Pendências (${open.length})`, items: c.pending, icon: "checklist", section: "pending" },
        { kind: "section", title: `Handoffs (${unread.length} abertos)`, items: c.handoffs, icon: "arrow-swap", section: "handoffs" },
        { kind: "section", title: "Decisões", items: c.decisions, icon: "law", section: "decisions" },
        { kind: "section", title: "Diário", items: c.journal.slice(-10).reverse(), icon: "notebook", section: "journal" },
      );
      return sections;
    }
    if (node.kind === "section") {
      if (node.section === "goal") return [{ kind: "text", text: c?.goal ?? "" }];
      return node.items.map((item) => ({ kind: "item", item, section: node.section }));
    }
    return [];
  }

  getTreeItem(node: CapsuleNode): vscode.TreeItem {
    if (node.kind === "text") {
      const item = new vscode.TreeItem(node.text);
      item.tooltip = node.text;
      return item;
    }
    if (node.kind === "section") {
      const expanded = node.section === "goal" || node.section === "pending" || node.section === "handoffs";
      const hasChildren = node.section === "goal" || node.items.length > 0;
      const collapsible = !hasChildren
        ? vscode.TreeItemCollapsibleState.None
        : expanded
          ? vscode.TreeItemCollapsibleState.Expanded
          : vscode.TreeItemCollapsibleState.Collapsed;
      const item = new vscode.TreeItem(node.title, collapsible);
      item.iconPath = new vscode.ThemeIcon(node.icon);
      return item;
    }
    const { item: it, section } = node;
    const label = section === "handoffs" && it.to ? `→ ${it.to}: ${it.text}` : it.text;
    const item = new vscode.TreeItem(label);
    item.tooltip = new vscode.MarkdownString(it.text);
    item.description = it.author;
    if (section === "pending") {
      item.contextValue = it.done ? "pending-done" : "pending";
      item.iconPath = new vscode.ThemeIcon(it.done ? "pass-filled" : "circle-large-outline");
    } else if (section === "handoffs") {
      item.iconPath = new vscode.ThemeIcon(it.done ? "pass" : "mail", it.done ? undefined : attention);
    }
    return item;
  }
}

export class FindingsView implements vscode.TreeDataProvider<Finding> {
  private readonly emitter = new vscode.EventEmitter<void>();
  readonly onDidChangeTreeData = this.emitter.event;

  constructor(private readonly store: Store) {
    store.onDidChange(() => this.emitter.fire());
  }

  getChildren(node?: Finding): Finding[] {
    return node ? [] : this.store.findings;
  }

  getTreeItem(f: Finding): vscode.TreeItem {
    const item = new vscode.TreeItem(f.title);
    item.description = f.detail;
    item.iconPath = new vscode.ThemeIcon("search-view-icon", attention);
    item.contextValue = f.command ? "finding-command" : "finding";
    item.tooltip = new vscode.MarkdownString([f.title, f.detail, f.suggestion, f.command && "`" + f.command + "`"].filter(Boolean).join("\n\n"));
    return item;
  }
}
