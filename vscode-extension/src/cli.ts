import { execFile } from "child_process";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import * as vscode from "vscode";

export function executable(): string {
  const configured = vscode.workspace.getConfiguration("trama").get<string>("executable", "").trim();
  if (configured) return configured;
  const candidates = [
    "/opt/homebrew/bin/trama",
    "/usr/local/bin/trama",
    path.join(os.homedir(), ".local", "bin", "trama"),
    "/Applications/Trama.app/Contents/MacOS/trama",
    path.join(os.homedir(), "Applications", "Trama.app", "Contents", "MacOS", "trama"),
  ];
  return candidates.find((c) => fs.existsSync(c)) ?? "trama";
}

function environment(): NodeJS.ProcessEnv {
  const home = vscode.workspace.getConfiguration("trama").get<string>("home", "").trim();
  return home ? { ...process.env, TRAMA_HOME: home } : process.env;
}

function failure(stdout: string, stderr: string, fallback: string): Error {
  for (const text of [stderr, stdout]) {
    try {
      const parsed = JSON.parse(text);
      if (parsed && typeof parsed.erro === "string") return new Error(parsed.erro);
    } catch {
      continue;
    }
  }
  const message = stderr.replace(/^erro:\s*/, "").trim();
  return new Error(message || fallback);
}

export function run(args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile(
      executable(),
      args,
      { env: environment(), maxBuffer: 32 * 1024 * 1024, timeout: 120_000 },
      (error, stdout, stderr) => {
        if (error) {
          const missing = (error as NodeJS.ErrnoException).code === "ENOENT";
          reject(missing ? new Error("não encontrei o comando `trama` · ajuste trama.executable nas configurações") : failure(stdout, stderr, error.message));
          return;
        }
        resolve(stdout);
      },
    );
  });
}

export async function json<T>(args: string[]): Promise<T> {
  return JSON.parse(await run([...args, "--json"])) as T;
}
