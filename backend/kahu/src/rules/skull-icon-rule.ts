import { Rule } from "./rule.js";
import type { SavedIssue } from "../types.js";

export class SkullIconRule extends Rule {
  readonly name = "CannotGetSkullIcon";
  readonly description =
    "Groups issues containing 'Cannot get skull icon' in the issue message";
  readonly logic =
    "1. Check if issue title contains 'Cannot get skull icon'\n" +
    "2. If not in title, check event message and exception value\n" +
    "3. Grouping key: CannotGetSkullIcon::message::cannot-get-skull-icon";

  private matches(issue: SavedIssue): boolean {
    const needle = "cannot get skull icon";

    if (issue.issue.title.toLowerCase().includes(needle)) return true;

    if (issue.issue.metadata.value?.toLowerCase().includes(needle)) return true;

    for (const evt of issue.events) {
      if (evt.message?.toLowerCase().includes(needle)) return true;

      const excValue = evt.exception?.values?.[0]?.value;
      if (excValue?.toLowerCase().includes(needle)) return true;
    }

    return false;
  }

  groupingKey(issue: SavedIssue): string | null {
    if (!this.matches(issue)) return null;
    return "CannotGetSkullIcon::message::cannot-get-skull-icon";
  }
}
