import { Rule } from "./rule.js";
import type { SavedIssue } from "../types.js";

const MATCH_TEXT = "Missing Offer Slot view at";

export class MissingOfferSlotViewRule extends Rule {
  readonly name = "MissingOfferSlotView";
  readonly description =
    "Groups issues whose title or message contains 'Missing Offer Slot view at'";
  readonly logic =
    "1. Check if the issue title contains 'Missing Offer Slot view at'\n" +
    "2. Otherwise check if any event message contains the same text\n" +
    "3. Grouping key: MissingOfferSlotView::MissingOfferSlotViewAt";

  groupingKey(issue: SavedIssue): string | null {
    if (this.hasMatch(issue.issue.title)) {
      return "MissingOfferSlotView::MissingOfferSlotViewAt";
    }

    for (const evt of issue.events) {
      if (this.hasMatch(evt.message)) {
        return "MissingOfferSlotView::MissingOfferSlotViewAt";
      }
    }

    return null;
  }

  private hasMatch(text?: string | null): boolean {
    if (!text) return false;
    return text.includes(MATCH_TEXT);
  }
}
