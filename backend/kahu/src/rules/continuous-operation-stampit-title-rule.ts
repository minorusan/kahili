import { Rule } from "./rule.js";
import type { SavedIssue } from "../types.js";

export class ContinuousOperationStampItTitleRule extends Rule {
  readonly name = "ContinuousOperationStampItTitle";
  readonly description =
    "Groups [ContinuousOperation] issues that mention StampIt or ScoreMaster in the title or list log";
  readonly logic =
    "1. Check if issue title contains [ContinuousOperation] or [ContinousOperation]\n" +
    "2. Combine title, event message, and exception value text\n" +
    "3. Look for StampIt or ScoreMaster in the combined text (case-insensitive)\n" +
    "4. Grouping key: ContinuousOperationStampItStacktrace::match";

  private static readonly TOKENS = ["stampit", "scoremaster"];
  private static readonly TITLE_MARKERS = [
    "[ContinuousOperation]",
    "[ContinousOperation]",
  ];

  groupingKey(issue: SavedIssue): string | null {
    const title = issue.issue.title || "";
    if (!this.titleMatches(title)) return null;

    const message = issue.events[0]?.message || "";
    const exceptionValue = issue.events[0]?.exception?.values?.[0]?.value || "";
    const combined = `${title}\n${message}\n${exceptionValue}`.toLowerCase();

    const hasMatch = ContinuousOperationStampItTitleRule.TOKENS.some((token) =>
      combined.includes(token)
    );
    if (!hasMatch) return null;

    return "ContinuousOperationStampItStacktrace::match";
  }

  private titleMatches(title: string): boolean {
    return ContinuousOperationStampItTitleRule.TITLE_MARKERS.some((marker) =>
      title.includes(marker)
    );
  }
}
