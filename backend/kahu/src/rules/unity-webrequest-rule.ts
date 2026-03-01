import { Rule } from "./rule.js";
import type { SavedIssue } from "../types.js";

export class UnityWebRequestRule extends Rule {
  readonly name = "UnityWebRequestException";
  readonly description =
    "Groups all UnityWebRequest exceptions into a single bucket";
  readonly logic =
    "1. Check if exception type contains 'UnityWebRequest'\n" +
    "2. Also check title and metadata.type for UnityWebRequest references\n" +
    "3. Also check if the topmost stack frame function starts with UnityWebRequest\n" +
    "4. Grouping key: UnityWebRequestException::all (single bucket)";

  private isUnityWebRequest(issue: SavedIssue): boolean {
    const UWR = "UnityWebRequest";

    // Check metadata.type
    if (issue.issue.metadata.type?.includes(UWR)) return true;

    // Check exception type from first event
    const excType = issue.events[0]?.exception?.values?.[0]?.type;
    if (excType?.includes(UWR)) return true;

    // Check title
    if (issue.issue.title.includes(UWR)) return true;

    // Check if topmost stack frame starts with UnityWebRequest
    const frames =
      issue.events[0]?.exception?.values?.[0]?.stacktrace?.frames;
    if (frames && frames.length > 0) {
      const top = frames[frames.length - 1];
      if (top.function?.startsWith("UnityEngine.Networking.UnityWebRequest")) {
        return true;
      }
    }

    return false;
  }

  groupingKey(issue: SavedIssue): string | null {
    if (!this.isUnityWebRequest(issue)) return null;
    return "UnityWebRequestException::all";
  }
}
