import { Rule } from "./rule.js";
import type { SavedIssue } from "../types.js";

export class CouponsServiceRule extends Rule {
  readonly name = "CouponsServiceNotInitialized";
  readonly description =
    "Groups issues where the Coupons service is not initialized";
  readonly logic =
    "1. Check if title contains '[Coupons]' and 'not initialized'\n" +
    "2. Also check exception value and event message as fallbacks\n" +
    "3. Grouping key: CouponsServiceNotInitialized::title-match (single bucket)";

  private matches(issue: SavedIssue): boolean {
    const title = issue.issue.title.toLowerCase();
    if (
      title.includes("[coupons]") &&
      title.includes("not initialized")
    ) {
      return true;
    }

    // Check exception value
    const excValue =
      issue.events[0]?.exception?.values?.[0]?.value?.toLowerCase() ?? "";
    if (
      excValue.includes("coupons service") &&
      excValue.includes("not initialized")
    ) {
      return true;
    }

    // Check metadata value
    const metaValue = (issue.issue.metadata.value ?? "").toLowerCase();
    if (
      metaValue.includes("coupons service") &&
      metaValue.includes("not initialized")
    ) {
      return true;
    }

    return false;
  }

  groupingKey(issue: SavedIssue): string | null {
    if (!this.matches(issue)) return null;
    return "CouponsServiceNotInitialized::title-match";
  }
}
