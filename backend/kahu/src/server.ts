import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { readFile } from "node:fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { log } from "./logger.js";
import type { SavedIssue } from "./types.js";
import type { MotherIssue } from "./rules/rule.js";
import {
  loadAllMotherIssues,
  loadMotherIssue as loadMotherIssueFromDisk,
  saveMotherIssue,
} from "./rules/storage.js";
import { loadAllIssues, loadIssue, saveIssue } from "./storage.js";
import { RULES, parseStackFromMessage, processRules } from "./rules/index.js";
import { backfillReport } from "./reporter.js";
import type { SentryClient, ArchiveParams } from "./sentry-client.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

function extractStackFrames(saved: SavedIssue) {
  // Try structured exception first
  const exc = saved.events[0]?.exception?.values?.[0];
  if (exc?.stacktrace?.frames?.length) {
    return {
      frames: exc.stacktrace.frames.map((f) => ({
        filename: f.filename ?? "",
        function: f.function ?? "",
        lineno: f.lineno ?? 0,
        inApp: f.inApp ?? false,
      })),
      errorType: exc.type,
      errorValue: exc.value,
    };
  }
  // Fall back to parsing from message/title
  const msg = saved.events[0]?.message || saved.issue.title || "";
  const frames = parseStackFromMessage(msg);
  if (frames.length > 0) {
    // Extract error type from first line
    const firstLine = msg.replace(/\\n/g, "\n").split("\n")[0] ?? "";
    // Try "ExceptionType: message" format
    const excMatch = firstLine.match(/^([A-Z]\w+(?:Exception|Error|Failure))\s*:\s*(.+)/);
    const errorType = excMatch ? excMatch[1] : undefined;
    const errorValue = excMatch ? excMatch[2].trim() : firstLine;
    return { frames, errorType, errorValue };
  }
  return null;
}

// ── helpers ──────────────────────────────────────────────────────────

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function linkify(text: string): string {
  return escapeHtml(text).replace(
    /(https?:\/\/[^\s<"']+)/g,
    '<a href="$1" target="_blank" rel="noopener">$1</a>',
  );
}

function relativeTime(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  const days = Math.floor(hrs / 24);
  if (days < 30) return `${days}d ago`;
  return `${Math.floor(days / 30)}mo ago`;
}

function truncate(s: string, n: number): string {
  return s.length > n ? s.slice(0, n - 1) + "…" : s;
}

function levelColor(level: string): string {
  switch (level) {
    case "fatal": return "#ff4444";
    case "error": return "#e03e2f";
    case "warning": return "#f5a623";
    case "info": return "#4b9fd5";
    case "debug": return "#8a8d91";
    default: return "#8a8d91";
  }
}

function json(res: ServerResponse, data: unknown, status = 200): void {
  const body = JSON.stringify(data);
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(body);
}

function html(res: ServerResponse, body: string, status = 200): void {
  res.writeHead(status, { "Content-Type": "text/html; charset=utf-8" });
  res.end(body);
}

// ── CSS ──────────────────────────────────────────────────────────────

const CSS = `
* { margin: 0; padding: 0; box-sizing: border-box; }
body { background: #0d1117; color: #c9d1d9; font-family: 'SF Mono', 'Cascadia Code', 'Fira Code', monospace; font-size: 14px; line-height: 1.5; }
a { color: #58a6ff; text-decoration: none; }
a:hover { text-decoration: underline; }
.container { max-width: 1400px; margin: 0 auto; padding: 24px; }
h1 { color: #f0f6fc; font-size: 20px; margin-bottom: 16px; font-weight: 600; }
h2 { color: #f0f6fc; font-size: 16px; margin: 20px 0 10px; font-weight: 600; }
h3 { color: #e6edf3; font-size: 14px; margin: 12px 0 6px; font-weight: 600; }

/* badges */
.badge { display: inline-block; padding: 2px 8px; border-radius: 3px; font-size: 12px; font-weight: 600; text-transform: uppercase; }
.tag { display: inline-block; padding: 2px 8px; border-radius: 3px; font-size: 12px; background: #1c2333; border: 1px solid #30363d; margin: 2px; }

/* tables */
table { width: 100%; border-collapse: collapse; margin-bottom: 16px; }
th { text-align: left; padding: 8px 12px; background: #161b22; border-bottom: 1px solid #30363d; color: #8b949e; font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px; }
td { padding: 8px 12px; border-bottom: 1px solid #21262d; vertical-align: top; }
tr.clickable { cursor: pointer; }
tr.clickable:hover { background: #161b22; }
tr.in-app { background: rgba(56,139,253,0.08); }

/* stats row */
.stats { display: flex; gap: 24px; margin: 16px 0; flex-wrap: wrap; }
.stat { background: #161b22; border: 1px solid #30363d; border-radius: 6px; padding: 12px 16px; }
.stat-label { font-size: 11px; color: #8b949e; text-transform: uppercase; letter-spacing: 0.5px; }
.stat-value { font-size: 18px; color: #f0f6fc; font-weight: 600; margin-top: 2px; }

/* header */
.header { display: flex; align-items: center; gap: 12px; margin-bottom: 8px; flex-wrap: wrap; }
.back { color: #8b949e; font-size: 13px; margin-bottom: 12px; display: inline-block; }
.back:hover { color: #c9d1d9; }

/* collapsible events */
details { margin-bottom: 12px; border: 1px solid #30363d; border-radius: 6px; overflow: hidden; }
summary { padding: 10px 14px; background: #161b22; cursor: pointer; font-weight: 600; font-size: 13px; }
summary:hover { background: #1c2333; }
details > .event-body { padding: 14px; }

/* contexts */
.ctx-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 10px; margin: 8px 0; }
.ctx-card { background: #161b22; border: 1px solid #30363d; border-radius: 6px; padding: 10px; }
.ctx-card h4 { font-size: 12px; color: #8b949e; text-transform: uppercase; margin-bottom: 6px; }
.ctx-card .kv { font-size: 13px; }
.ctx-card .kv span:first-child { color: #8b949e; }

/* breadcrumbs */
.bc-table td { font-size: 12px; padding: 4px 8px; }
.bc-table .bc-ts { color: #8b949e; white-space: nowrap; }
.bc-table .bc-cat { color: #d2a8ff; }

/* tabs */
.tabs { display: flex; gap: 0; border-bottom: 1px solid #30363d; margin-bottom: 20px; }
.tab { padding: 10px 20px; color: #8b949e; font-size: 14px; font-weight: 600; border-bottom: 2px solid transparent; margin-bottom: -1px; cursor: pointer; }
.tab:hover { color: #c9d1d9; text-decoration: none; }
.tab.active { color: #f0f6fc; border-bottom-color: #f78166; }
`;

function renderTabs(active: "issues" | "mother-issues"): string {
  return `<nav class="tabs">
  <a class="tab${active === "issues" ? " active" : ""}" href="/">Issues</a>
  <a class="tab${active === "mother-issues" ? " active" : ""}" href="/mother-issues">Mother Issues</a>
</nav>`;
}

function page(title: string, body: string): string {
  return `<!DOCTYPE html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title}</title>
<style>${CSS}</style>
</head><body>
<div class="container">
${body}
</div>
</body></html>`;
}

// ── list page ────────────────────────────────────────────────────────

function renderListPage(issues: SavedIssue[]): string {
  const sorted = issues.sort(
    (a, b) => new Date(b.issue.lastSeen).getTime() - new Date(a.issue.lastSeen).getTime(),
  );
  const rows = sorted
    .map((s) => {
      const i = s.issue;
      return `<tr class="clickable" onclick="location.href='/issue/${escapeHtml(i.id)}'">
        <td style="white-space:nowrap">${escapeHtml(i.shortId)}</td>
        <td>${escapeHtml(truncate(i.title, 80))}</td>
        <td><span class="badge" style="background:${levelColor(i.level)}">${escapeHtml(i.level)}</span></td>
        <td style="text-align:right">${escapeHtml(i.count)}</td>
        <td style="text-align:right">${i.userCount}</td>
        <td>${escapeHtml(i.project?.slug || "")}</td>
        <td style="white-space:nowrap;color:#8b949e" title="${escapeHtml(i.lastSeen)}">${relativeTime(i.lastSeen)}</td>
      </tr>`;
    })
    .join("\n");

  return page(`kahu — Issues`, `
  ${renderTabs("issues")}
  <h1>Issues (${issues.length})</h1>
  <table>
    <thead><tr>
      <th>ID</th><th>Title</th><th>Level</th><th style="text-align:right">Events</th><th style="text-align:right">Users</th><th>Project</th><th>Last Seen</th>
    </tr></thead>
    <tbody>${rows}</tbody>
  </table>`);
}

// ── detail page ──────────────────────────────────────────────────────

function renderDetailPage(saved: SavedIssue): string {
  const i = saved.issue;
  const evts = (saved.events || []).slice(0, 5);

  // tags
  const tags = (i.tags || [])
    .map((t) => `<span class="tag">${escapeHtml(t.key)}=${escapeHtml(t.value)}</span>`)
    .join(" ");

  // events
  const eventBlocks = evts.map((evt, idx) => {
    const userGeo = evt.user?.geo
      ? `${evt.user.geo.city || ""}, ${evt.user.geo.region || ""}, ${evt.user.geo.country_code || ""}`
      : "—";
    const userId = evt.user?.id || evt.user?.username || evt.user?.email || "—";
    const userIp = evt.user?.ip_address || "—";

    // exception
    let exceptionHtml = "";
    if (evt.exception?.values?.length) {
      exceptionHtml = evt.exception.values
        .map((ex) => {
          let frames = "";
          if (ex.stacktrace?.frames?.length) {
            const rows = [...ex.stacktrace.frames]
              .reverse()
              .map((f) => {
                const cls = f.inApp ? ' class="in-app"' : "";
                return `<tr${cls}><td>${escapeHtml(f.filename || "")}</td><td>${escapeHtml(f.function || "")}</td><td>${f.lineno ?? ""}${f.colno ? ":" + f.colno : ""}</td><td>${f.inApp ? "✓" : ""}</td></tr>`;
              })
              .join("");
            frames = `<table><thead><tr><th>File</th><th>Function</th><th>Line</th><th>App</th></tr></thead><tbody>${rows}</tbody></table>`;
          }
          return `<h3>${escapeHtml(ex.type)}: ${linkify(ex.value)}</h3>${frames}`;
        })
        .join("");
    }

    // breadcrumbs (last 20)
    let breadcrumbsHtml = "";
    const bcValues = evt.breadcrumbs?.values || [];
    if (bcValues.length) {
      const bcs = bcValues.slice(-20);
      const bcRows = bcs
        .map((b) => {
          const ts = b.timestamp ? new Date(b.timestamp).toISOString().slice(11, 23) : "";
          return `<tr><td class="bc-ts">${escapeHtml(ts)}</td><td class="bc-cat">${escapeHtml(b.category || "")}</td><td>${linkify(b.message || "")}</td></tr>`;
        })
        .join("");
      breadcrumbsHtml = `<h3>Breadcrumbs</h3><table class="bc-table"><tbody>${bcRows}</tbody></table>`;
    }

    // contexts
    let contextsHtml = "";
    const ctxKeys = Object.keys(evt.contexts || {}).filter(
      (k) => evt.contexts[k] && typeof evt.contexts[k] === "object",
    );
    if (ctxKeys.length) {
      const cards = ctxKeys
        .map((k) => {
          const obj = evt.contexts[k] as Record<string, unknown>;
          const kvs = Object.entries(obj)
            .filter(([ck]) => ck !== "type")
            .map(([ck, cv]) => `<div class="kv"><span>${escapeHtml(ck)}: </span><span>${linkify(String(cv ?? ""))}</span></div>`)
            .join("");
          return `<div class="ctx-card"><h4>${escapeHtml(k)}</h4>${kvs}</div>`;
        })
        .join("");
      contextsHtml = `<h3>Contexts</h3><div class="ctx-grid">${cards}</div>`;
    }

    const open = idx === 0 ? " open" : "";
    return `<details${open}>
      <summary>Event #${idx + 1} — ${escapeHtml(evt.datetime)} — ${escapeHtml(evt.eventID.slice(0, 12))}</summary>
      <div class="event-body">
        <div class="stats">
          <div class="stat"><div class="stat-label">Time</div><div class="stat-value" style="font-size:14px">${escapeHtml(evt.datetime)}</div></div>
          <div class="stat"><div class="stat-label">User</div><div class="stat-value" style="font-size:14px">${escapeHtml(String(userId))}</div></div>
          <div class="stat"><div class="stat-label">IP</div><div class="stat-value" style="font-size:14px">${escapeHtml(userIp)}</div></div>
          <div class="stat"><div class="stat-label">Geo</div><div class="stat-value" style="font-size:14px">${escapeHtml(userGeo)}</div></div>
          <div class="stat"><div class="stat-label">Release</div><div class="stat-value" style="font-size:14px">${escapeHtml(evt.release || "—")}</div></div>
        </div>
        ${exceptionHtml}
        ${breadcrumbsHtml}
        ${contextsHtml}
      </div>
    </details>`;
  }).join("\n");

  return page(`${escapeHtml(i.title)} — kahu`, `
  ${renderTabs("issues")}
  <a class="back" href="/">← Back to issues</a>
  <div class="header">
    <h1>${escapeHtml(i.title)}</h1>
    <span class="badge" style="background:${levelColor(i.level)}">${escapeHtml(i.level)}</span>
    <span class="badge" style="background:#30363d">${escapeHtml(i.status)}</span>
  </div>
  <div style="margin-bottom:12px">
    <a href="${escapeHtml(i.permalink)}" target="_blank" rel="noopener">${escapeHtml(i.shortId)} → Sentry</a>
  </div>
  <div class="stats">
    <div class="stat"><div class="stat-label">Events</div><div class="stat-value">${escapeHtml(i.count)}</div></div>
    <div class="stat"><div class="stat-label">Users</div><div class="stat-value">${i.userCount}</div></div>
    <div class="stat"><div class="stat-label">Project</div><div class="stat-value" style="font-size:14px">${escapeHtml(i.project?.slug || "")}</div></div>
    <div class="stat"><div class="stat-label">First Seen</div><div class="stat-value" style="font-size:14px">${relativeTime(i.firstSeen)}</div></div>
    <div class="stat"><div class="stat-label">Last Seen</div><div class="stat-value" style="font-size:14px">${relativeTime(i.lastSeen)}</div></div>
  </div>
  <h2>Tags</h2>
  <div style="margin-bottom:16px">${tags || "<span style='color:#8b949e'>No tags</span>"}</div>
  <h2>Events (${evts.length})</h2>
  ${eventBlocks}`);
}

// ── mother issue list page ───────────────────────────────────────────

function renderMotherIssueListPage(motherIssues: MotherIssue[]): string {
  const sorted = motherIssues.sort(
    (a, b) =>
      new Date(b.metrics.lastSeen).getTime() -
      new Date(a.metrics.lastSeen).getTime()
  );
  const rows = sorted
    .map((mi) => {
      return `<tr class="clickable" onclick="location.href='/mother-issue/${escapeHtml(mi.id)}'">
        <td style="white-space:nowrap">${escapeHtml(mi.id)}</td>
        <td>${escapeHtml(truncate(mi.title, 80))}</td>
        <td><span class="badge" style="background:${levelColor(mi.level)}">${escapeHtml(mi.level)}</span></td>
        <td>${escapeHtml(mi.errorType)}</td>
        <td style="text-align:right">${mi.metrics.totalOccurrences}</td>
        <td style="text-align:right">${mi.metrics.affectedUsers}</td>
        <td style="text-align:right">${mi.childIssueIds.length}</td>
        <td style="white-space:nowrap;color:#8b949e" title="${escapeHtml(mi.metrics.lastSeen)}">${relativeTime(mi.metrics.lastSeen)}</td>
      </tr>`;
    })
    .join("\n");

  return page(`kahu — Mother Issues`, `
  ${renderTabs("mother-issues")}
  <h1>Mother Issues (${motherIssues.length})</h1>
  <table>
    <thead><tr>
      <th>ID</th><th>Title</th><th>Level</th><th>Type</th><th style="text-align:right">Events</th><th style="text-align:right">Users</th><th style="text-align:right">Children</th><th>Last Seen</th>
    </tr></thead>
    <tbody>${rows}</tbody>
  </table>`);
}

// ── mother issue detail page ────────────────────────────────────────

function renderMotherIssueDetailPage(
  mi: MotherIssue,
  childIssues: SavedIssue[]
): string {
  // Stack trace
  let stackHtml = "";
  if (mi.stackTrace?.frames?.length) {
    const frameRows = [...mi.stackTrace.frames]
      .reverse()
      .map((f) => {
        const cls = f.inApp ? ' class="in-app"' : "";
        return `<tr${cls}><td>${escapeHtml(f.filename || "")}</td><td>${escapeHtml(f.function || "")}</td><td>${f.lineno ?? ""}</td><td>${f.inApp ? "✓" : ""}</td></tr>`;
      })
      .join("");
    stackHtml = `<h2>Stack Trace</h2>
    <table><thead><tr><th>File</th><th>Function</th><th>Line</th><th>App</th></tr></thead><tbody>${frameRows}</tbody></table>`;
  }

  // Child issues table
  const childRows = childIssues
    .sort(
      (a, b) =>
        new Date(b.issue.lastSeen).getTime() -
        new Date(a.issue.lastSeen).getTime()
    )
    .map((s) => {
      const i = s.issue;
      return `<tr class="clickable" onclick="location.href='/issue/${escapeHtml(i.id)}'">
        <td style="white-space:nowrap">${escapeHtml(i.shortId)}</td>
        <td>${escapeHtml(truncate(i.title, 80))}</td>
        <td><span class="badge" style="background:${levelColor(i.level)}">${escapeHtml(i.level)}</span></td>
        <td style="text-align:right">${escapeHtml(i.count)}</td>
        <td style="text-align:right">${i.userCount}</td>
        <td style="white-space:nowrap;color:#8b949e" title="${escapeHtml(i.lastSeen)}">${relativeTime(i.lastSeen)}</td>
      </tr>`;
    })
    .join("\n");

  return page(`${escapeHtml(mi.title)} — Mother Issue — kahu`, `
  ${renderTabs("mother-issues")}
  <a class="back" href="/mother-issues">← Back to mother issues</a>
  <div class="header">
    <h1>${escapeHtml(mi.title)}</h1>
    <span class="badge" style="background:${levelColor(mi.level)}">${escapeHtml(mi.level)}</span>
    <span class="badge" style="background:#30363d">${escapeHtml(mi.ruleName)}</span>
  </div>
  <div style="margin-bottom:12px;color:#8b949e;font-size:13px">
    ${escapeHtml(mi.groupingKey)}
  </div>
  <div class="stats">
    <div class="stat"><div class="stat-label">Total Events</div><div class="stat-value">${mi.metrics.totalOccurrences}</div></div>
    <div class="stat"><div class="stat-label">Affected Users</div><div class="stat-value">${mi.metrics.affectedUsers}</div></div>
    <div class="stat"><div class="stat-label">Child Issues</div><div class="stat-value">${mi.childIssueIds.length}</div></div>
    <div class="stat"><div class="stat-label">First Seen</div><div class="stat-value" style="font-size:14px">${relativeTime(mi.metrics.firstSeen)}</div></div>
    <div class="stat"><div class="stat-label">Last Seen</div><div class="stat-value" style="font-size:14px">${relativeTime(mi.metrics.lastSeen)}</div></div>
  </div>
  ${stackHtml}
  <h2>Child Issues (${childIssues.length})</h2>
  <table>
    <thead><tr>
      <th>ID</th><th>Title</th><th>Level</th><th style="text-align:right">Events</th><th style="text-align:right">Users</th><th>Last Seen</th>
    </tr></thead>
    <tbody>${childRows}</tbody>
  </table>`);
}

// ── router ───────────────────────────────────────────────────────────

let sentryClient: SentryClient | null = null;

function readBody(req: IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    req.on("data", (chunk: Buffer) => chunks.push(chunk));
    req.on("end", () => resolve(Buffer.concat(chunks).toString()));
    req.on("error", reject);
  });
}

async function handleRequest(req: IncomingMessage, res: ServerResponse): Promise<void> {
  const url = req.url || "/";

  // API: list issues
  if (url === "/api/issues") {
    const issues = await loadAllIssues();
    const summaries = issues
      .sort((a, b) => new Date(b.issue.lastSeen).getTime() - new Date(a.issue.lastSeen).getTime())
      .map((s) => {
        const i = s.issue;
        const stack = extractStackFrames(s);
        return {
          id: i.id,
          shortId: i.shortId,
          title: i.title,
          level: i.level,
          status: i.status,
          count: i.count,
          userCount: i.userCount,
          firstSeen: i.firstSeen,
          lastSeen: i.lastSeen,
          platform: i.project?.slug,
          permalink: i.permalink,
          stackTrace: stack ? { frames: stack.frames } : undefined,
          errorType: stack?.errorType,
          errorValue: stack?.errorValue,
        };
      });
    return json(res, summaries);
  }

  // API: single issue
  const apiMatch = url.match(/^\/api\/issues\/(\d+)$/);
  if (apiMatch) {
    const saved = await loadIssue(apiMatch[1]);
    if (!saved) return json(res, { error: "Not found" }, 404);
    return json(res, saved);
  }

  // API: list rules
  if (url === "/api/rules") {
    const rules = RULES.map((r) => ({ name: r.name, description: r.description, logic: r.logic }));
    return json(res, rules);
  }

  // API: list mother issues
  if (url === "/api/mother-issues") {
    const mis = await loadAllMotherIssues();
    const sorted = mis.sort(
      (a, b) =>
        new Date(b.metrics.lastSeen).getTime() -
        new Date(a.metrics.lastSeen).getTime()
    );
    return json(res, sorted);
  }

  // API: create manual mother issue from a single incoming issue
  // Accepts issueId directly or a Sentry URL. Fetches from Sentry if not locally cached.
  if (req.method === "POST" && url === "/api/mother-issues/manual") {
    const body = JSON.parse(await readBody(req)) as { issueId?: string; sentryUrl?: string };

    let issueId = body.issueId;
    if (!issueId && body.sentryUrl) {
      // Extract issue ID from Sentry URL, e.g. https://org.sentry.io/issues/12345/...
      const m = body.sentryUrl.match(/\/issues\/(\d+)/);
      if (m) issueId = m[1];
    }
    if (!issueId) return json(res, { error: "issueId or sentryUrl is required" }, 400);

    let saved = await loadIssue(issueId);

    // If not cached locally, try fetching from Sentry
    if (!saved && sentryClient) {
      try {
        const sentryIssue = await sentryClient.getIssue(issueId);
        const events = await sentryClient.getIssueFullEvents(issueId, 5);
        await saveIssue(sentryIssue as unknown as import("./types.js").SentryIssue, events);
        saved = await loadIssue(issueId);
      } catch (err) {
        log.error(`[Server] Failed to fetch issue ${issueId} from Sentry:`, err);
      }
    }

    if (!saved) return json(res, { error: "Issue not found locally or on Sentry" }, 404);

    const { createHash } = await import("node:crypto");
    const groupingKey = `Manual::${body.issueId}`;
    const id = createHash("sha256").update(groupingKey).digest("hex").slice(0, 16);

    const extracted = extractStackFrames(saved);
    const stackTrace = extracted ? { frames: extracted.frames } : undefined;
    const smartlookUrls: string[] = [];
    for (const evt of saved.events) {
      const sl = evt.contexts?.smartlook as { url?: string; [key: string]: unknown } | undefined;
      if (sl?.url) smartlookUrls.push(sl.url);
      for (const tag of evt.tags ?? []) {
        if (tag.key === "SmartlookUrl" && tag.value) smartlookUrls.push(tag.value);
      }
    }

    const now = new Date().toISOString();
    const mi: MotherIssue = {
      id,
      groupingKey,
      ruleName: "Manual",
      title: saved.issue.title,
      errorType: saved.issue.metadata.type || "Error",
      level: saved.issue.level,
      metrics: {
        totalOccurrences: parseInt(saved.issue.count, 10) || 0,
        affectedUsers: saved.issue.userCount || 0,
        firstSeen: saved.issue.firstSeen,
        lastSeen: saved.issue.lastSeen,
      },
      childIssueIds: [saved.issue.id],
      childStatuses: [saved.issue.status ?? "unresolved"],
      sentryLinks: saved.issue.permalink ? [saved.issue.permalink] : [],
      smartlookUrls: [...new Set(smartlookUrls)],
      stackTrace,
      firstSeenRelease: saved.firstSeenRelease,
      allChildrenArchived: saved.issue.status !== "unresolved",
      createdAt: now,
      updatedAt: now,
    };

    await saveMotherIssue(mi);
    log.info(`[Server] Created manual mother issue ${id} for issue ${body.issueId}`);
    return json(res, mi, 201);
  }

  // API: sync a mother issue's child statuses from Sentry
  const syncMatch = url.match(/^\/api\/mother-issues\/([a-f0-9]+)\/sync$/);
  if (req.method === "POST" && syncMatch) {
    const mi = await loadMotherIssueFromDisk(syncMatch[1]);
    if (!mi) return json(res, { error: "Mother issue not found" }, 404);
    if (!sentryClient) return json(res, { error: "Sentry client not initialized" }, 500);

    let updated = 0;
    for (let i = 0; i < mi.childIssueIds.length; i++) {
      try {
        const fresh = await sentryClient.getIssue(mi.childIssueIds[i]);
        const saved = await loadIssue(mi.childIssueIds[i]);
        if (saved && fresh.status !== saved.issue.status) {
          saved.issue.status = fresh.status;
          saved.issue.statusDetails = fresh.statusDetails ?? {};
          await saveIssue(saved.issue, saved.events);
          updated++;
        }
        mi.childStatuses[i] = fresh.status ?? "unresolved";
      } catch (err) {
        log.warn(`[Server] Failed to sync child ${mi.childIssueIds[i]}: ${err}`);
      }
    }

    mi.allChildrenArchived = mi.childStatuses.length > 0 &&
      mi.childStatuses.every((s) => s !== "unresolved");
    mi.updatedAt = new Date().toISOString();
    await saveMotherIssue(mi);

    if (updated > 0) {
      log.info(`[Server] Synced mother issue ${mi.id}: ${updated} child statuses updated, allArchived=${mi.allChildrenArchived}`);
    }
    return json(res, { ok: true, updated, allChildrenArchived: mi.allChildrenArchived });
  }

  // API: single mother issue
  const apiMotherMatch = url.match(/^\/api\/mother-issues\/([a-f0-9]+)$/);
  if (apiMotherMatch) {
    const mi = await loadMotherIssueFromDisk(apiMotherMatch[1]);
    if (!mi) return json(res, { error: "Not found" }, 404);
    return json(res, mi);
  }

  // API: backfill daily report for a specific date
  if (req.method === "POST" && url === "/api/backfill-report") {
    let body = "";
    await new Promise<void>((resolve) => {
      req.on("data", (chunk: Buffer) => { body += chunk.toString(); });
      req.on("end", resolve);
    });
    try {
      const { date } = JSON.parse(body) as { date?: string };
      if (!date) return json(res, { error: "date is required (YYYY-MM-DD)" }, 400);
      await backfillReport(date);
      return json(res, { ok: true, date });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      log.error(`[Server] Backfill failed: ${msg}`);
      return json(res, { error: msg }, 500);
    }
  }

  // API: archive issues with comment
  if (req.method === "POST" && url === "/api/archive-issues") {
    if (!sentryClient) {
      return json(res, { error: "Sentry client not initialized" }, 500);
    }
    let body: {
      issueIds?: string[];
      comment?: string;
      archiveParams?: ArchiveParams;
    };
    try {
      const raw = await readBody(req);
      body = JSON.parse(raw);
    } catch {
      return json(res, { error: "invalid JSON body" }, 400);
    }

    if (!body.issueIds?.length) {
      return json(res, { error: "issueIds array is required" }, 400);
    }
    if (!body.archiveParams) {
      return json(res, { error: "archiveParams is required" }, 400);
    }

    const results: Array<{ issueId: string; ok: boolean; error?: string }> = [];

    for (const issueId of body.issueIds) {
      try {
        // Add comment first (if provided), then archive
        if (body.comment) {
          await sentryClient.addIssueComment(issueId, body.comment);
        }
        await sentryClient.archiveIssue(issueId, body.archiveParams);
        results.push({ issueId, ok: true });
        log.info(`[Server] Archived issue ${issueId}`);
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        log.error(`[Server] Failed to archive issue ${issueId}: ${msg}`);
        results.push({ issueId, ok: false, error: msg });
      }
    }

    // Sync: update local statuses for archived issues and re-run rules
    const archivedIds = results.filter((r) => r.ok).map((r) => r.issueId);
    if (archivedIds.length > 0) {
      for (const id of archivedIds) {
        try {
          const saved = await loadIssue(id);
          if (saved && saved.issue.status === "unresolved") {
            saved.issue.status = "ignored";
            await saveIssue(saved.issue, saved.events);
          }
        } catch (err) {
          log.warn(`[Server] Failed to update local status for ${id}: ${err}`);
        }
      }
      // Re-run rules so mother issue allChildrenArchived updates immediately
      try {
        await processRules();
        log.info(`[Server] Re-processed rules after archiving ${archivedIds.length} issues`);
      } catch (err) {
        log.warn(`[Server] Failed to re-process rules after archive: ${err}`);
      }
    }

    const allOk = results.every((r) => r.ok);
    return json(res, { ok: allOk, results }, allOk ? 200 : 207);
  }

  // HTML: mother issues list
  if (url === "/mother-issues") {
    const mis = await loadAllMotherIssues();
    return html(res, renderMotherIssueListPage(mis));
  }

  // HTML: mother issue detail
  const motherDetailMatch = url.match(/^\/mother-issue\/([a-f0-9]+)$/);
  if (motherDetailMatch) {
    const mi = await loadMotherIssueFromDisk(motherDetailMatch[1]);
    if (!mi) return html(res, "<h1>Mother issue not found</h1>", 404);
    // Load child issues
    const children: SavedIssue[] = [];
    for (const childId of mi.childIssueIds) {
      const child = await loadIssue(childId);
      if (child) children.push(child);
    }
    return html(res, renderMotherIssueDetailPage(mi, children));
  }

  // HTML: detail page
  const detailMatch = url.match(/^\/issue\/(\d+)$/);
  if (detailMatch) {
    const saved = await loadIssue(detailMatch[1]);
    if (!saved) return html(res, "<h1>Issue not found</h1>", 404);
    return html(res, renderDetailPage(saved));
  }

  // HTML: list page
  if (url === "/") {
    const issues = await loadAllIssues();
    return html(res, renderListPage(issues));
  }

  // 404
  res.writeHead(404);
  res.end("Not found");
}

// ── server ───────────────────────────────────────────────────────────

export function startServer(port: number, client?: SentryClient): void {
  if (client) sentryClient = client;
  const server = createServer((req, res) => {
    handleRequest(req, res).catch((err) => {
      log.error("HTTP handler error", err);
      if (!res.headersSent) {
        res.writeHead(500);
        res.end("Internal server error");
      }
    });
  });

  server.listen(port, () => {
    log.info(`Web UI listening on http://localhost:${port}`);
  });
}
