// Sentry API response types — ported from egregor kadmon

export interface SentryUser {
  id?: string | number;
  email?: string;
  username?: string;
  ip_address?: string;
  segment?: string;
  geo?: {
    city?: string;
    country_code?: string;
    region?: string;
  };
  [key: string]: unknown;
}

export interface SentryStackFrame {
  filename: string;
  function: string;
  module?: string;
  lineno: number;
  colno?: number;
  absPath?: string;
  contextLine?: string;
  preContext?: string[];
  postContext?: string[];
  inApp: boolean;
  vars?: Record<string, unknown>;
}

export interface SentryBreadcrumb {
  type?:
    | "default"
    | "debug"
    | "error"
    | "navigation"
    | "http"
    | "info"
    | "query"
    | "transaction"
    | "ui";
  category?: string;
  message?: string;
  level?: "fatal" | "error" | "warning" | "info" | "debug";
  timestamp: string;
  data?: Record<string, unknown>;
}

export interface SentryContexts {
  browser?: {
    name: string;
    version: string;
    type: "browser";
  };
  os?: {
    name: string;
    version: string;
    type: "os";
  };
  runtime?: {
    name: string;
    version: string;
    type: "runtime";
  };
  device?: {
    name?: string;
    family?: string;
    model?: string;
    arch?: string;
    battery_level?: number;
    orientation?: "portrait" | "landscape";
    type: "device";
  };
  smartlook?: {
    url?: string;
    recording_id?: string;
    session_id?: string;
    visitor_id?: string;
    type?: "smartlook";
    [key: string]: unknown;
  };
  [key: string]:
    | {
        type?: string;
        [key: string]: unknown;
      }
    | undefined;
}

export interface SentryIssue {
  id: string;
  shortId: string;
  title: string;
  culprit: string;
  permalink: string;
  logger: string | null;
  level: "error" | "warning" | "fatal" | "info" | "debug" | "sample";
  status: "resolved" | "unresolved" | "ignored";
  statusDetails: Record<string, unknown>;
  type: string;
  metadata: {
    title: string;
    type: string;
    value: string;
    filename?: string;
    function?: string;
  };
  count: string;
  userCount: number;
  numComments: number;
  firstSeen: string;
  lastSeen: string;
  project: {
    id: string;
    name: string;
    slug: string;
  };
  isBookmarked: boolean;
  isSubscribed: boolean;
  hasSeen: boolean;
  tags: Array<{ key: string; value: string; count?: number }>;
  assignedTo?: {
    id: string;
    name: string;
    email: string;
  } | null;
  stats?: {
    "24h"?: Array<[number, number]>;
    "30d"?: Array<[number, number]>;
  };
}

export interface SentryEventSummary {
  id: string;
  eventID: string;
  groupID: string;
  projectID: string;
  title: string;
  message: string;
  platform: string;
  "event.type": string;
  location: string;
  culprit: string;
  dateCreated: string;
  user: SentryUser | null;
  tags: Array<{ key: string; value: string }>;
}

export interface SentryFullEvent {
  eventID: string;
  groupID: string;
  projectID: string;
  release?: string | null;
  dist?: string | null;
  platform: string;
  message: string;
  datetime: string;
  type: "error" | "transaction" | "default";
  metadata: {
    type: string;
    value: string;
    filename?: string;
    function?: string;
  };
  tags: Array<{ key: string; value: string }>;
  user: SentryUser | null;
  contexts: SentryContexts;
  extra: Record<string, unknown>;
  breadcrumbs: {
    values: SentryBreadcrumb[];
  };
  exception?: {
    values: Array<{
      type: string;
      value: string;
      module?: string;
      threadId?: number | null;
      mechanism?: {
        type: string;
        handled: boolean;
      };
      stacktrace?: {
        frames: SentryStackFrame[];
      };
    }>;
  };
  request?: {
    url: string;
    method?: string;
    data?: unknown;
    query_string?: string | Array<[string, string]>;
    cookies?: string | Record<string, string>;
    headers?: Record<string, string>;
    env?: Record<string, string>;
  };
  sdk?: {
    name: string;
    version: string;
  };
  environment?: string;
  fingerprint?: string[];
}

// Alert rule types

export interface SentryAlertRule {
  id: string;
  name: string;
  status: string;
  dateCreated: string;
  dateModified?: string;
  lastTriggered?: string;
  environment?: string | null;
  conditions?: unknown[];
  actions?: unknown[];
  frequency?: number;
  [key: string]: unknown;
}

export interface AlertGroupHistoryItem {
  group: SentryIssue;
  count: number;
  lastTriggered: string;
  eventId: string;
}

// Poll state types

export interface ProcessedIssueState {
  lastTriggered: string;
  lastEventId: string;
  count: number;
}

export interface PollState {
  lastPollTime: string | null;
  alertRuleId: string | null;
  alertRuleName: string | null;
  processedIssues: Record<string, ProcessedIssueState>;
}

// Saved issue file format

export interface SavedIssue {
  issue: SentryIssue;
  events: SentryFullEvent[];
  savedAt: string;
  updatedAt: string;
}
