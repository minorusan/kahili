import { createWriteStream, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import type { WriteStream } from "node:fs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const LOGS_DIR = join(__dirname, "..", "logs");

type LogLevel = "info" | "warn" | "error";

class Logger {
  private stream: WriteStream;
  private sessionFile: string;

  constructor() {
    mkdirSync(LOGS_DIR, { recursive: true });

    const now = new Date();
    const stamp = now.toISOString().replace(/[:.]/g, "-").replace("T", "_").replace("Z", "");
    this.sessionFile = join(LOGS_DIR, `${stamp}.log`);
    this.stream = createWriteStream(this.sessionFile, { flags: "a" });
  }

  private format(level: LogLevel, message: string): string {
    const ts = new Date().toISOString();
    return `[${ts}] [${level.toUpperCase()}] ${message}`;
  }

  private write(level: LogLevel, message: string): void {
    const line = this.format(level, message);
    this.stream.write(line + "\n");

    // Also print to stdout/stderr
    if (level === "error") {
      console.error(line);
    } else {
      console.log(line);
    }
  }

  info(message: string): void {
    this.write("info", message);
  }

  warn(message: string): void {
    this.write("warn", message);
  }

  error(message: string, err?: unknown): void {
    let msg = message;
    if (err instanceof Error) {
      msg += ` ${err.message}`;
      if (err.stack) {
        msg += `\n${err.stack}`;
      }
    } else if (err !== undefined) {
      msg += ` ${String(err)}`;
    }
    this.write("error", msg);
  }

  close(): void {
    this.stream.end();
  }

  getSessionFile(): string {
    return this.sessionFile;
  }
}

export const log = new Logger();
