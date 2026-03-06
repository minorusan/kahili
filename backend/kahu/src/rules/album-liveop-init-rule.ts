import { Rule } from "./rule.js";
import type { SavedIssue } from "../types.js";

export class AlbumLiveOpInitRule extends Rule {
  readonly name = "AlbumLiveOpInit";
  readonly description =
    "Groups issues with message '[Album] Album model has not being initialize with LiveOp.'";
  readonly logic =
    "1. Check if issue title or event message contains the exact string '[Album] Album model has not being initialize with LiveOp.'\n" +
    "2. Grouping key: AlbumLiveOpInit::message-match";

  private static readonly TARGET =
    "[Album] Album model has not being initialize with LiveOp.";

  groupingKey(issue: SavedIssue): string | null {
    const target = AlbumLiveOpInitRule.TARGET;

    if (issue.issue.title.includes(target)) {
      return "AlbumLiveOpInit::message-match";
    }

    for (const evt of issue.events) {
      if (evt.message?.includes(target)) {
        return "AlbumLiveOpInit::message-match";
      }
    }

    return null;
  }
}
