import type {
  SentryEventSummary,
  SentryFullEvent,
  SentryAlertRule,
  AlertGroupHistoryItem,
} from "./types.js";
import { log } from "./logger.js";

const BASE_URL = "https://sentry.io/api/0";

export interface SentryClientConfig {
  token: string;
  org: string;
  project: string;
}

export class SentryClient {
  private token: string;
  private org: string;
  private project: string;

  constructor(config: SentryClientConfig) {
    this.token = config.token;
    this.org = config.org;
    this.project = config.project;
  }

  private async request(endpoint: string): Promise<Response> {
    const url = `${BASE_URL}${endpoint}`;
    const res = await fetch(url, {
      headers: {
        Authorization: `Bearer ${this.token}`,
      },
    });

    if (res.status === 429) {
      const retryAfter = parseInt(res.headers.get("Retry-After") || "60", 10);
      log.warn(`[Sentry] Rate limited. Retrying after ${retryAfter}s...`);
      await new Promise((resolve) => setTimeout(resolve, retryAfter * 1000));
      return this.request(endpoint);
    }

    if (!res.ok) {
      const body = await res.text();
      throw new Error(
        `Sentry API error ${res.status}: ${res.statusText} — ${body}`
      );
    }

    return res;
  }

  // =========================================================================
  // Alert Rules API
  // =========================================================================

  async getAlertRules(): Promise<SentryAlertRule[]> {
    const res = await this.request(
      `/projects/${this.org}/${this.project}/rules/`
    );
    return (await res.json()) as SentryAlertRule[];
  }

  async findAlertRuleByName(name: string): Promise<SentryAlertRule | null> {
    const rules = await this.getAlertRules();
    const lower = name.toLowerCase();
    return rules.find((r) => r.name.toLowerCase() === lower) ?? null;
  }

  async getAlertRuleGroupHistory(
    ruleId: string,
    start: string,
    end: string
  ): Promise<AlertGroupHistoryItem[]> {
    const params = new URLSearchParams();
    params.set("start", start);
    params.set("end", end);

    const res = await this.request(
      `/projects/${this.org}/${this.project}/rules/${ruleId}/group-history/?${params.toString()}`
    );
    return (await res.json()) as AlertGroupHistoryItem[];
  }

  // =========================================================================
  // Issues & Events API
  // =========================================================================

  async getIssueEvents(
    issueId: string,
    limit: number = 5
  ): Promise<SentryEventSummary[]> {
    const res = await this.request(
      `/organizations/${this.org}/issues/${issueId}/events/`
    );
    const all = (await res.json()) as SentryEventSummary[];
    return all.slice(0, limit);
  }

  async getFullEvent(eventId: string): Promise<SentryFullEvent> {
    const res = await this.request(
      `/projects/${this.org}/${this.project}/events/${eventId}/`
    );
    const raw = (await res.json()) as Record<string, unknown>;
    return trimEvent(raw);
  }

  async getIssueFullEvents(
    issueId: string,
    limit: number = 5
  ): Promise<SentryFullEvent[]> {
    const summaries = await this.getIssueEvents(issueId, limit);
    const fullEvents: SentryFullEvent[] = [];

    for (const summary of summaries) {
      try {
        const fullEvent = await this.getFullEvent(summary.eventID);
        fullEvents.push(fullEvent);
      } catch (err) {
        log.error(
          `[Sentry] Failed to fetch full event ${summary.eventID}:`,
          err
        );
      }
    }

    return fullEvents;
  }
}

/**
 * Extract typed fields from raw Sentry event response.
 * The API returns exception/breadcrumbs/request inside an `entries[]` array.
 * We pull them out into top-level fields and drop entries, _meta, and other junk.
 */
function trimEvent(raw: Record<string, unknown>): SentryFullEvent {
  // Extract from entries[]
  const entries = raw.entries as
    | Array<{ type: string; data: Record<string, unknown> }>
    | undefined;

  let exception: SentryFullEvent["exception"] | undefined;
  let breadcrumbs: SentryFullEvent["breadcrumbs"] | undefined;
  let request: SentryFullEvent["request"] | undefined;

  if (entries) {
    for (const entry of entries) {
      if (entry.type === "exception") {
        exception = entry.data as unknown as SentryFullEvent["exception"];
      } else if (entry.type === "breadcrumbs") {
        breadcrumbs = entry.data as unknown as SentryFullEvent["breadcrumbs"];
      } else if (entry.type === "request") {
        request = entry.data as unknown as SentryFullEvent["request"];
      }
    }
  }

  return {
    eventID: raw.eventID as string,
    groupID: raw.groupID as string,
    projectID: raw.projectID as string,
    release: (raw.release as { version?: string })?.version ?? (raw.release as string | null) ?? undefined,
    dist: raw.dist as string | null | undefined,
    platform: raw.platform as string,
    message: raw.message as string,
    datetime: (raw.dateCreated as string) ?? (raw.datetime as string),
    type: raw.type as SentryFullEvent["type"],
    metadata: raw.metadata as SentryFullEvent["metadata"],
    tags: raw.tags as SentryFullEvent["tags"],
    user: raw.user as SentryFullEvent["user"],
    contexts: raw.contexts as SentryFullEvent["contexts"],
    extra: (raw.context as Record<string, unknown>) ?? {},
    breadcrumbs: breadcrumbs ?? { values: [] },
    exception,
    request,
    sdk: raw.sdk as SentryFullEvent["sdk"],
    environment: raw.environment as string | undefined,
    fingerprint: (raw.fingerprints as string[]) ?? undefined,
  };
}
