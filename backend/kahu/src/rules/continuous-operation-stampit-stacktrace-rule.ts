import { Rule } from "./rule.js";
import type { SavedIssue, SentryStackFrame } from "../types.js";

export class ContinuousOperationStampItStacktraceRule extends Rule {
  readonly name = "ContinuousOperationStampItStacktrace";
  readonly description =
    "Groups [ContinuousOperation] / [ContinousOperation] issues whose stacktrace mentions StampIt or ScoreMaster (case-insensitive)";
  readonly logic =
    "1. Check if issue title contains [ContinuousOperation] or [ContinousOperation]\n" +
    "2. Extract stacktrace text from the event message and exception value\n" +
    "3. Look for StampIt or ScoreMaster in structured stack frames or stacktrace text (case-insensitive)\n" +
    "4. Grouping key: ContinuousOperationStampItStacktrace::match";

  private static readonly TOKENS = ["stampit", "scoremaster"];
  private static readonly TITLE_MARKERS = [
    "[ContinuousOperation]",
    "[ContinousOperation]",
  ];

  groupingKey(issue: SavedIssue): string | null {
    const title = issue.issue.title || "";
    if (!this.titleMatches(title)) return null;

    const message = issue.events[0]?.message || "";
    const exceptionValue = issue.events[0]?.exception?.values?.[0]?.value || "";
    const stackText = this.extractStackText(message);
    const frames = issue.events[0]?.exception?.values?.[0]?.stacktrace?.frames;
    const combined = `${stackText}\n${exceptionValue}`;
    const combinedLower = combined.toLowerCase();

    const hasMatch = ContinuousOperationStampItStacktraceRule.TOKENS.some(
      (token) =>
        this.hasTokenInFrames(frames, token) || combinedLower.includes(token)
    );

    if (!hasMatch) return null;

    return "ContinuousOperationStampItStacktrace::match";
  }

  private hasTokenInFrames(
    frames: SentryStackFrame[] | undefined,
    token: string
  ): boolean {
    if (!frames || frames.length === 0) return false;
    return frames.some((frame) => {
      const fn = (frame.function || "").toLowerCase();
      const file = (frame.filename || "").toLowerCase();
      const module = (frame.module || "").toLowerCase();
      return fn.includes(token) || file.includes(token) || module.includes(token);
    });
  }

  private extractStackText(message: string): string {
    const normalized = message.replace(/\\n/g, "\n");
    const parts = normalized.split("\n\n");
    if (parts.length <= 1) return normalized;
    return parts.slice(1).join("\n\n");
  }

  private titleMatches(title: string): boolean {
    return ContinuousOperationStampItStacktraceRule.TITLE_MARKERS.some(
      (marker) => title.includes(marker)
    );
  }
}
