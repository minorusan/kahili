import { Rule } from "./rule.js";
import type { SavedIssue } from "../types.js";

/**
 * Matches liveop IDs in various formats:
 * - UUIDs: 550e8400-e29b-41d4-a716-446655440000
 * - Hex strings (16+ chars): a1b2c3d4e5f67890
 * - Numeric IDs (4+ digits): 123456
 */
const LIVEOP_ID_PATTERN =
  /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[0-9a-f]{16,}|\d{4,}/gi;

export class LiveopIdRule extends Rule {
  readonly name = "LiveopId";
  readonly description =
    "Groups issues whose titles differ only by a liveop ID, ignoring the variable ID part";
  readonly logic =
    "1. Check if issue title contains 'liveop' (case-insensitive)\n" +
    "2. Replace all ID-like tokens (UUIDs, hex strings, numeric IDs) with a placeholder\n" +
    "3. Use the normalized title as the grouping key\n" +
    "4. Grouping key: LiveopId::title::<normalized-title>";

  private containsLiveop(title: string): boolean {
    return /liveop/i.test(title);
  }

  private normalizeTitle(title: string): string {
    return title.replace(LIVEOP_ID_PATTERN, "<id>").trim();
  }

  groupingKey(issue: SavedIssue): string | null {
    const title = issue.issue.title;
    if (!this.containsLiveop(title)) return null;
    const normalized = this.normalizeTitle(title);
    return `LiveopId::title::${normalized}`;
  }
}
