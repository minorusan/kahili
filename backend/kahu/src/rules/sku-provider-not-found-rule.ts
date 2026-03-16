import { Rule } from "./rule.js";
import type { SavedIssue } from "../types.js";

export class SkuProviderNotFoundRule extends Rule {
  readonly name = "SkuProviderNotFound";
  readonly description =
    "Groups SkuProvider-not-found issues by the missing SKU provider type";
  readonly logic =
    "1. Check if title/message contains '[SkuManager] SkuProvider for type <Type> not found'\n" +
    "2. Extract the <Type> token after 'SkuProvider for type ' and before ' not found'\n" +
    "3. Grouping key: SkuProviderNotFound::type::<extracted-type>";

  private readonly MARKER = "SkuProvider for type ";

  groupingKey(issue: SavedIssue): string | null {
    const title = issue.issue.title;
    const keyFromTitle = this.extractType(title);
    if (keyFromTitle) return `SkuProviderNotFound::type::${keyFromTitle}`;

    const message = issue.events[0]?.message ?? "";
    const keyFromMessage = this.extractType(message);
    if (keyFromMessage) return `SkuProviderNotFound::type::${keyFromMessage}`;

    return null;
  }

  private extractType(text: string): string | null {
    if (!text.includes(this.MARKER)) return null;
    const match = text.match(/SkuProvider for type ([^\\s\\n]+) not found/);
    if (!match?.[1]) return null;
    return match[1].trim();
  }
}
