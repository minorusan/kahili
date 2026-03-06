import { Rule } from "./rule.js";
import type { SavedIssue } from "../types.js";

const FRAMEWORK_PREFIXES = [
  "System.",
  "Cysharp.",
  "UnityEngine.",
  "TMPro.",
  "Sentry.",
];

export class NreManagedStacktraceRule extends Rule {
  readonly name = "NreManagedStacktrace";
  readonly description =
    "Groups NullReferenceException issues by their managed (in-app) stacktrace sequence";
  readonly logic =
    "1. Check if the issue is a NullReferenceException\n" +
    "2. Parse stacktrace from message text (first segment before async re-throw)\n" +
    "3. Keep only verbose-format lines, skip compact Sentry duplicates\n" +
    "4. Strip 'at ' prefix, filter to managed (non-framework) frames, deduplicate\n" +
    "5. Grouping key: NreManagedStacktrace::<managed sequence>";

  groupingKey(issue: SavedIssue): string | null {
    if (!this.isNre(issue)) return null;

    const managed = this.getManagedSequence(issue);
    if (!managed) return null;

    return `NreManagedStacktrace::${managed}`;
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

  private getManagedSequence(issue: SavedIssue): string | null {
    // Try structured exception frames first
    const exceptions = issue.events[0]?.exception?.values;
    if (exceptions && exceptions.length > 0) {
      const allFrames = exceptions[0]?.stacktrace?.frames;
      if (allFrames && allFrames.length > 0) {
        const managed = allFrames
          .filter((f) => f.inApp)
          .map((f) => f.function || "<unknown>");
        if (managed.length > 0) {
          return [...new Set(managed)].join(" -> ");
        }
      }
    }

    // Fall back to parsing stack from message text
    const msg = issue.events[0]?.message || issue.issue.title || "";
    return this.parseManagedSequenceFromMessage(msg);
  }

  private parseManagedSequenceFromMessage(msg: string): string | null {
    // Take only first stack segment (before async re-throw marker)
    const firstSegment = msg.split(/---\s*End of stack trace/)[0];
    const lines = firstSegment.replace(/\\n/g, "\n").split("\n");
    if (lines.length < 2) return null;

    const seen = new Set<string>();
    const managed: string[] = [];

    for (let i = 1; i < lines.length; i++) {
      const line = lines[i].trim();
      if (!line) continue;

      // Skip compact Sentry-format duplicates (ClassName:Method or <Method>d__N:MoveNext)
      // These appear at the end of Unity messages and duplicate the verbose lines above.
      // They use ":" as method separator and lack the full class hierarchy.
      if (!line.startsWith("at ") && /\w:\w/.test(line)) continue;

      // Extract function name from verbose format: "at Namespace.Class.Method (at file.cs:123)"
      const atMatch = line.match(/\(at\s+(.+?):(\d+)\)/);
      let fn = atMatch
        ? line.slice(0, line.indexOf("(at")).trim()
        : line;
      fn = fn.replace(/\s*\(.*$/, "").trim();
      if (!fn) continue;

      // Strip leading "at "
      fn = fn.replace(/^at\s+/, "");

      // Normalize async state machine patterns to plain method names:
      //   Class+<Method>d__N.MoveNext  →  Class.Method
      //   Class.<Method>d__N.MoveNext  →  Class.Method
      fn = fn.replace(/[+.]<(\w+)>d__\d+\.MoveNext$/, ".$1");

      if (FRAMEWORK_PREFIXES.some((p) => fn.startsWith(p))) continue;
      if (seen.has(fn)) continue;
      seen.add(fn);
      managed.push(fn);
    }

    return managed.length > 0 ? managed.join(" -> ") : null;
  }
}
