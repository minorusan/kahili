import { createHash } from "node:crypto";
import { Rule } from "./rule.js";
import type { SavedIssue, SentryStackFrame } from "../types.js";

export class ManagedStacktraceRule extends Rule {
  readonly name = "ManagedStacktrace";
  readonly description =
    "Groups issues that share the same managed (in-app) stacktrace sequence";
  readonly logic =
    "1. Extract exception stacktrace frames from the first event\n" +
    "2. Filter to only in-app (managed) frames\n" +
    "3. If no managed frames found, skip (return null)\n" +
    "4. Build a sequence string from each frame's function name\n" +
    "5. Hash the sequence to produce a stable grouping key\n" +
    "6. Grouping key: ManagedStacktrace::sequence::<hash>";

  groupingKey(issue: SavedIssue): string | null {
    const frames = this.getManagedFrames(issue);
    if (!frames || frames.length === 0) return null;

    // Build sequence from function names (order matters)
    const sequence = frames
      .map((f) => f.function || "<unknown>")
      .join(" -> ");

    const hash = createHash("sha256").update(sequence).digest("hex").slice(0, 12);
    return `ManagedStacktrace::sequence::${hash}`;
  }

  private getManagedFrames(issue: SavedIssue): SentryStackFrame[] | null {
    // Try structured exception stacktrace from first event
    const exceptions = issue.events[0]?.exception?.values;
    if (!exceptions || exceptions.length === 0) return null;

    // Use the first exception's stacktrace (primary exception)
    const allFrames = exceptions[0]?.stacktrace?.frames;
    if (!allFrames || allFrames.length === 0) return null;

    // Filter to managed/in-app frames only
    const managed = allFrames.filter((f) => f.inApp);
    return managed.length > 0 ? managed : null;
  }
}
