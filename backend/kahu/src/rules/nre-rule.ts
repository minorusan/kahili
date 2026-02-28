import { createHash } from "node:crypto";
import { Rule } from "./rule.js";
import type { SavedIssue } from "../types.js";

export class NreRule extends Rule {
  readonly name = "NullReferenceException";
  readonly description =
    "Groups NullReferenceException issues by full stack trace hash";

  private isNre(issue: SavedIssue): boolean {
    const NRE = "NullReferenceException";
    // Check metadata.type (some Sentry SDKs populate it)
    if (issue.issue.metadata.type === NRE) return true;
    // Check event exception type (most reliable source)
    const excType = issue.events[0]?.exception?.values?.[0]?.type;
    if (excType === NRE) return true;
    // Check title as fallback
    if (issue.issue.title.startsWith(NRE)) return true;
    return false;
  }

  groupingKey(issue: SavedIssue): string | null {
    if (!this.isNre(issue)) return null;
    const errorType = "NullReferenceException";

    const frames =
      issue.events[0]?.exception?.values?.[0]?.stacktrace?.frames;
    if (!frames || frames.length === 0) {
      return `${errorType}::stacktrace::no-frames`;
    }

    const parts = frames.map(
      (f) => `${f.function || "?"}@${f.filename || "?"}`
    );
    const raw = parts.join("|");
    const hash = createHash("sha256").update(raw).digest("hex").slice(0, 16);
    return `${errorType}::stacktrace::${hash}`;
  }
}
