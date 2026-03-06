import { Rule } from "./rule.js";
import type { SavedIssue } from "../types.js";

export class ContinousOperationScoreMasterStampItPopupRule extends Rule {
  readonly name = "ContinuousOperationScoreMaster";
  readonly description =
    "Groups [ContinuousOperation] issues mentioning ScoreMasterInfoPopupController";
  readonly logic =
    "1. Check if issue title, event message, or exception value contains [ContinuousOperation]\n" +
    "2. Check if any of those contain ScoreMasterInfoPopupController\n" +
    "3. Grouping key: ContinuousOperationScoreMaster::match";

  groupingKey(issue: SavedIssue): string | null {
    const title = issue.issue.title || "";
    const message = issue.events[0]?.message || "";
    const exceptionValue = issue.events[0]?.exception?.values?.[0]?.value || "";
    const combined = `${title}\n${message}\n${exceptionValue}`;

    if (!combined.includes("[ContinuousOperation]")) return null;
    if (!combined.includes("ScoreMasterInfoPopupController")) return null;

    return "ContinuousOperationScoreMaster::match";
  }
}
