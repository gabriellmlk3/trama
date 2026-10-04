export interface Agent {
  sessao: string;
  trama: string;
  repo: string;
  estado: string;
  mensagem?: string;
}

export interface RepoStatus {
  repo: string;
  alias: string;
  label?: string;
  path: string;
  exists: boolean;
  base: string;
  branch: string;
  ahead: number;
  behind: number;
  changed: number;
  conflict?: string;
  agents: Agent[];
  error?: string;
}

export interface LiveTrama {
  slug: string;
  titulo: string;
  branch: string;
  base?: string;
  repos: string[];
  estado: string;
  tarefa?: string;
  caminho: string;
  capsula: string;
  status: RepoStatus[];
}

export interface OverallState {
  root: string;
  tramas: LiveTrama[];
  agents: Agent[];
}

export interface CapsuleItem {
  index: number;
  text: string;
  author?: string;
  done: boolean;
  from?: string;
  to?: string;
}

export interface Capsule {
  trama: string;
  path: string;
  exists: boolean;
  goal: string;
  decisions: CapsuleItem[];
  handoffs: CapsuleItem[];
  pending: CapsuleItem[];
  journal: CapsuleItem[];
}

export interface Finding {
  type: string;
  repo?: string;
  trama?: string;
  title: string;
  detail: string;
  suggestion?: string;
  command?: string;
}

export const AgentState = { working: "trabalhando", waiting: "aguardando", done: "concluiu" };
export const TramaState = { active: "ativa", parked: "estacionada", archived: "arquivada" };
