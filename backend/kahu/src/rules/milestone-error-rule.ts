import { Rule } from "./rule.js";
import type { SavedIssue } from "../types.js";

const PREFIX = "[Milestone Error]";

export class MilestoneErrorRule extends Rule {
  readonly name = "MilestoneError";
  readonly description =
    "Groups all issues with [Milestone Error] prefix into a single mother issue";
  readonly logic =
    "1. Check if issue title starts with '[Milestone Error]'\n" +
    "2. If yes, return fixed grouping key — all milestone errors become one mother issue\n" +
    "3. If no, return null (skip)";

  groupingKey(issue: SavedIssue): string | null {
    if (!issue.issue.title.startsWith(PREFIX)) return null;
    return "MilestoneError::prefix::[Milestone Error]";
  }
}
