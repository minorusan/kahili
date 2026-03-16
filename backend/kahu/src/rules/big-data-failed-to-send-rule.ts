import { Rule } from "./rule.js";
import type { SavedIssue } from "../types.js";

const TITLE_MARKER = "Big data failed to send.";
const STATUS_CODE_PATTERN = /HTTP\/1\.1\s+(\d{3})/i;

export class BigDataFailedToSendRule extends Rule {
  readonly name = "BigDataFailedToSend";
  readonly description =
    "Groups 'Big data failed to send' issues by the HTTP status code when present";
  readonly logic =
    "1. Check if the issue title contains 'Big data failed to send.'\n" +
    "2. Extract HTTP status code from the title or first event message\n" +
    "3. If no status code found, use a generic key\n" +
    "4. Grouping key: BigDataFailedToSend::status::<code>";

  private extractStatusCode(issue: SavedIssue): string | null {
    const titleMatch = issue.issue.title.match(STATUS_CODE_PATTERN);
    if (titleMatch?.[1]) return titleMatch[1];

    const msg = issue.events[0]?.message;
    const msgMatch = msg?.match(STATUS_CODE_PATTERN);
    if (msgMatch?.[1]) return msgMatch[1];

    return null;
  }

  groupingKey(issue: SavedIssue): string | null {
    const title = issue.issue.title;
    if (!title.includes(TITLE_MARKER)) return null;

    const statusCode = this.extractStatusCode(issue);
    if (statusCode) {
      return `BigDataFailedToSend::status::${statusCode}`;
    }

    return "BigDataFailedToSend::status::unknown";
  }
}
