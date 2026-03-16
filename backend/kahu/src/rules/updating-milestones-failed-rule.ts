import { Rule } from "./rule.js";
import type { SavedIssue } from "../types.js";

const TITLE_PREFIX = "Updating milestones failed";

export class UpdatingMilestonesFailedRule extends Rule {
  readonly name = "UpdatingMilestonesFailed";
  readonly description =
    "Groups issues whose title starts with 'Updating milestones failed' into a single mother issue";
  readonly logic =
    "1. Check if issue title starts with 'Updating milestones failed'\n" +
    "2. If yes, return fixed grouping key — all matching issues become one mother issue\n" +
    "3. If no, return null (skip)";

  groupingKey(issue: SavedIssue): string | null {
    if (!issue.issue.title.startsWith(TITLE_PREFIX)) return null;
    return "UpdatingMilestonesFailed::title::Updating milestones failed";
  }
}
