import type { SavedIssue, SentryStackFrame } from "../types.js";

export interface MotherIssue {
  id: string; // sha256(groupingKey).slice(0,16)
  groupingKey: string; // e.g. "NullReferenceException::stacktrace::abc123"
  ruleName: string; // which rule created this
  title: string; // from first matched issue
  errorType: string; // e.g. "NullReferenceException"
  level: string; // highest severity among children
  metrics: {
    totalOccurrences: number; // sum of all child issue counts
    affectedUsers: number; // sum of userCounts
    firstSeen: string;
    lastSeen: string;
  };
  childIssueIds: string[]; // sentry issue IDs grouped here
  repoPath?: string; // local repo path, backfilled from settings
  stackTrace?: {
    frames: Array<{
      filename: string;
      function: string;
      lineno: number;
      inApp: boolean;
    }>;
  };
  createdAt: string;
  updatedAt: string;
}

export abstract class Rule {
  abstract readonly name: string;
  abstract readonly description: string;
  abstract groupingKey(issue: SavedIssue): string | null;
}
