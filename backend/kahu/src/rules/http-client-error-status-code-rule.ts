import { Rule } from "./rule.js";
import type { SavedIssue } from "../types.js";

const ERROR_TYPE = "HTTPClientError";
const STATUS_CODE_PATTERN = /status code:\s*(\d{3})/i;

export class HttpClientErrorStatusCodeRule extends Rule {
  readonly name = "HTTPClientErrorStatusCode";
  readonly description =
    "Groups HTTPClientError issues by the HTTP status code in the error message";
  readonly logic =
    "1. Check if issue is HTTPClientError via metadata.type, exception type, or title\n" +
    "2. Extract HTTP status code from title or metadata.value (e.g. 'status code: 502')\n" +
    "3. If both match, group by status code\n" +
    "4. Grouping key: HTTPClientErrorStatusCode::status::<code>";

  private isHttpClientError(issue: SavedIssue): boolean {
    if (issue.issue.metadata.type === ERROR_TYPE) return true;
    const excType = issue.events[0]?.exception?.values?.[0]?.type;
    if (excType === ERROR_TYPE) return true;
    if (issue.issue.title.startsWith(ERROR_TYPE)) return true;
    return false;
  }

  private extractStatusCode(issue: SavedIssue): string | null {
    const titleMatch = issue.issue.title.match(STATUS_CODE_PATTERN);
    if (titleMatch?.[1]) return titleMatch[1];

    const metaValue = issue.issue.metadata.value;
    const metaMatch = metaValue?.match(STATUS_CODE_PATTERN);
    if (metaMatch?.[1]) return metaMatch[1];

    const eventValue = issue.events[0]?.metadata?.value;
    const eventMatch = eventValue?.match(STATUS_CODE_PATTERN);
    if (eventMatch?.[1]) return eventMatch[1];

    return null;
  }

  groupingKey(issue: SavedIssue): string | null {
    if (!this.isHttpClientError(issue)) return null;
    const statusCode = this.extractStatusCode(issue);
    if (!statusCode) return null;
    return `HTTPClientErrorStatusCode::status::${statusCode}`;
  }
}
