import { Rule } from "./rule.js";
import type { SavedIssue } from "../types.js";

const DOWNLOAD_KEYWORDS = [
  "download",
  "asset",
  "assetbundle",
  "addressable",
  "bundle",
  "cdn",
  "fetch",
  "load asset",
  "remote asset",
];

/**
 * Matches URL-like paths:  https://cdn.example.com/path/to/asset.bundle
 * or partial paths:        assets/environment/tree.prefab
 */
const URL_PATTERN =
  /(?:https?:\/\/[^\s"']+\/([^\s"'?#]+)|(?:assets\/[^\s"',;)]+))/i;

/**
 * Matches quoted or bracketed asset names:  'MyAsset', "MyAsset", [MyAsset]
 */
const QUOTED_ASSET_PATTERN = /['"\[]([A-Za-z0-9_\-./]+(?:\.[a-z0-9]+)?)['"\]]/;

export class AssetDownloadRule extends Rule {
  readonly name = "AssetDownload";
  readonly description =
    "Groups asset download errors by asset name, regardless of failure reason";
  readonly logic =
    "1. Combine title + exception value + message into one text blob\n" +
    "2. Check for download-related keywords (download, asset, assetbundle, cdn, etc.)\n" +
    "3. Extract asset name via URL pattern (https://.../<asset>) or quoted/bracketed name\n" +
    "4. Normalize asset name to lowercase\n" +
    "5. Grouping key: AssetDownload::asset::<normalized-name>";

  private isAssetDownloadIssue(text: string): boolean {
    const lower = text.toLowerCase();
    return DOWNLOAD_KEYWORDS.some((kw) => lower.includes(kw));
  }

  private extractAssetName(text: string): string | null {
    // Try URL pattern first (most specific)
    const urlMatch = text.match(URL_PATTERN);
    if (urlMatch) {
      // urlMatch[1] is the path segment from a full URL, urlMatch[0] is the
      // full match (could be an assets/ relative path)
      const raw = urlMatch[1] ?? urlMatch[0];
      // Normalise: strip query/fragment leftovers, lowercase
      return raw.replace(/[?#].*$/, "").toLowerCase();
    }

    // Try quoted/bracketed asset name
    const quotedMatch = text.match(QUOTED_ASSET_PATTERN);
    if (quotedMatch) {
      return quotedMatch[1].toLowerCase();
    }

    return null;
  }

  groupingKey(issue: SavedIssue): string | null {
    const title = issue.issue.title;
    const exceptionValue = issue.events[0]?.exception?.values?.[0]?.value ?? "";
    const message = issue.events[0]?.message ?? "";

    // Combine all text sources for keyword detection
    const combined = `${title}\n${exceptionValue}\n${message}`;

    if (!this.isAssetDownloadIssue(combined)) return null;

    // Try to extract asset name from each source (prefer title, then exception, then message)
    const assetName =
      this.extractAssetName(title) ??
      this.extractAssetName(exceptionValue) ??
      this.extractAssetName(message);

    if (!assetName) return null;

    return `AssetDownload::asset::${assetName}`;
  }
}
