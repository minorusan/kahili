import { Rule } from "./rule.js";
import type { SavedIssue } from "../types.js";

export class ContinuousOperationChallengePopupRule extends Rule {
  readonly name = "ContinuousOperationChallengePopup";
  readonly description =
    "Groups issues containing [ContinuousOperation] and ChallengePopupLogic in message";
  readonly logic =
    "1. Check if issue title or event message contains [ContinuousOperation]\n" +
    "2. Check if issue title or event message contains ChallengePopupLogic\n" +
    "3. Both must be present to match\n" +
    "4. Grouping key: ContinuousOperationChallengePopup::match";

  groupingKey(issue: SavedIssue): string | null {
    const title = issue.issue.title || "";
    const message = issue.events[0]?.message || "";
    const exceptionValue = issue.events[0]?.exception?.values?.[0]?.value || "";
    const combined = `${title}\n${message}\n${exceptionValue}`;

    const hasContinuousOperation = combined.includes("[ContinuousOperation]");
    const hasChallengePopupLogic = combined.includes("ChallengePopupLogic");

    if (hasContinuousOperation && hasChallengePopupLogic) {
      return `ContinuousOperationChallengePopup::match`;
    }

    return null;
  }
}
