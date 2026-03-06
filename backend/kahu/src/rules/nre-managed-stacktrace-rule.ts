import { createHash } from "node:crypto";
import { Rule } from "./rule.js";
import type { SavedIssue, SentryStackFrame } from "../types.js";

export class NreManagedStacktraceRule extends Rule {
  readonly name = "NreManagedStacktrace";
  readonly description =
    "Groups NullReferenceException issues by their managed (in-app) stacktrace sequence";
  readonly logic =
    "1. Check if the issue is a NullReferenceException (metadata type or title)\n" +
    "2. Extract exception stacktrace frames from the first event\n" +
    "3. Filter to only in-app (managed) frames\n" +
    "4. If no managed frames found, skip (return null)\n" +
    "5. Build a sequence string from each frame's function name\n" +
    "6. Hash the sequence to produce a stable grouping key\n" +
    "7. Grouping key: NreManagedStacktrace::sequence::<hash>";

  groupingKey(issue: SavedIssue): string | null {
    if (!this.isNre(issue)) return null;

    const frames = this.getManagedFrames(issue);
    if (!frames || frames.length === 0) return null;

    const sequence = frames
      .map((f) => f.function || "<unknown>")
      .join(" -> ");

    const hash = createHash("sha256").update(sequence).digest("hex").slice(0, 12);
    return `NreManagedStacktrace::sequence::${hash}`;
  }

  private isNre(issue: SavedIssue): boolean {
    const type = (issue.issue.metadata.type ?? "").toLowerCase();
    if (type.includes("nullreferenceexception")) return true;

    const title = issue.issue.title.toLowerCase();
    if (title.includes("nullreferenceexception")) return true;

    const excType =
      issue.events[0]?.exception?.values?.[0]?.type?.toLowerCase() ?? "";
    if (excType.includes("nullreferenceexception")) return true;

    return false;
  }

  private getManagedFrames(issue: SavedIssue): SentryStackFrame[] | null {
    const exceptions = issue.events[0]?.exception?.values;
    if (!exceptions || exceptions.length === 0) return null;

    const allFrames = exceptions[0]?.stacktrace?.frames;
    if (!allFrames || allFrames.length === 0) return null;

    const managed = allFrames.filter((f) => f.inApp);
    return managed.length > 0 ? managed : null;
  }
}
