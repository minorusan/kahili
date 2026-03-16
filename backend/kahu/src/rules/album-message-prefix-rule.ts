import { Rule } from "./rule.js";
import type { SavedIssue } from "../types.js";

const ALBUM_PREFIX = "[Album]";

export class AlbumMessagePrefixRule extends Rule {
  readonly name = "AlbumMessagePrefix";
  readonly description =
    "Groups issues whose title or message starts with the [Album] prefix";
  readonly logic =
    "1. Check if issue title starts with '[Album]' (ignoring leading whitespace)\n" +
    "2. Otherwise check if any event message starts with '[Album]'\n" +
    "3. Grouping key: AlbumMessagePrefix::Album";

  groupingKey(issue: SavedIssue): string | null {
    if (this.hasAlbumPrefix(issue.issue.title)) {
      return "AlbumMessagePrefix::Album";
    }

    for (const evt of issue.events) {
      if (this.hasAlbumPrefix(evt.message)) {
        return "AlbumMessagePrefix::Album";
      }
    }

    return null;
  }

  private hasAlbumPrefix(text?: string | null): boolean {
    if (!text) return false;
    return text.trimStart().startsWith(ALBUM_PREFIX);
  }
}
