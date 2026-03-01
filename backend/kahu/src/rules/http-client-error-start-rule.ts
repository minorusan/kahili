import { Rule } from "./rule.js";
import type { SavedIssue } from "../types.js";

const ERROR_TYPE = "HTTPClientError";

export class HttpClientErrorStartRule extends Rule {
  readonly name = "HTTPClientErrorInStart";
  readonly description =
    "Groups HTTPClientError issues occurring in the start function into a single mother issue";
  readonly logic =
    "1. Check if issue is HTTPClientError via metadata.type, exception type, or title\n" +
    "2. Check if error occurs in a 'start' function via culprit, metadata.function, or stack frames\n" +
    "3. If both match, return fixed grouping key — all HTTPClientError-in-start errors become one mother issue\n" +
    "4. Grouping key: HTTPClientErrorInStart::function::start";

  private isHttpClientError(issue: SavedIssue): boolean {
    if (issue.issue.metadata.type === ERROR_TYPE) return true;
    const excType = issue.events[0]?.exception?.values?.[0]?.type;
    if (excType === ERROR_TYPE) return true;
    if (issue.issue.title.startsWith(ERROR_TYPE)) return true;
    return false;
  }

  private involvesStart(issue: SavedIssue): boolean {
    const startPattern = /\bstart\b/i;

    // Check culprit (e.g. "MyClass.Start")
    if (startPattern.test(issue.issue.culprit)) return true;

    // Check metadata.function
    if (issue.issue.metadata.function && startPattern.test(issue.issue.metadata.function)) return true;

    // Check stack frames for a function named "start"
    const frames = issue.events[0]?.exception?.values?.[0]?.stacktrace?.frames;
    if (frames?.some((f) => startPattern.test(f.function))) return true;

    return false;
  }

  groupingKey(issue: SavedIssue): string | null {
    if (!this.isHttpClientError(issue)) return null;
    if (!this.involvesStart(issue)) return null;
    return "HTTPClientErrorInStart::function::start";
  }
}
