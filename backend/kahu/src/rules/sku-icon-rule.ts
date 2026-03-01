import { Rule } from "./rule.js";
import type { SavedIssue } from "../types.js";

export class SkuIconRule extends Rule {
  readonly name = "SkuIcon";
  readonly description =
    "Groups issues containing 'Can not get SKU icon' by the SKU string value";
  readonly logic =
    "1. Check if issue title contains 'Can not get SKU icon'\n" +
    "2. Extract the SKU string from the title after 'Can not get SKU icon string '\n" +
    "3. If no specific SKU found, use a generic key\n" +
    "4. Grouping key: SkuIcon::sku::<extracted-sku>";

  private readonly MARKER = "Can not get SKU icon";

  groupingKey(issue: SavedIssue): string | null {
    const title = issue.issue.title;
    if (!title.includes(this.MARKER)) return null;

    // Try to extract the SKU value after "Can not get SKU icon string "
    const prefix = "Can not get SKU icon string ";
    const idx = title.indexOf(prefix);
    if (idx !== -1) {
      const sku = title.slice(idx + prefix.length).trim();
      if (sku) {
        return `SkuIcon::sku::${sku}`;
      }
    }

    return `SkuIcon::sku::unknown`;
  }
}
