import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { readdir, readFile } from "node:fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { log } from "./logger.js";
import type { SavedIssue } from "./types.js";
import type { MotherIssue } from "./rules/rule.js";
import {
  loadAllMotherIssues,
  loadMotherIssue as loadMotherIssueFromDisk,
} from "./rules/storage.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ISSUES_DIR = join(__dirname, "..", "data", "issues");

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

async function loadAllIssues(): Promise<SavedIssue[]> {
  let files: string[];
  try {
    files = await readdir(ISSUES_DIR);
  } catch {
    return [];
  }
  const jsonFiles = files.filter((f) => f.endsWith(".json"));
  const issues: SavedIssue[] = [];
  for (const file of jsonFiles) {
    try {
      const raw = await readFile(join(ISSUES_DIR, file), "utf-8");
      issues.push(JSON.parse(raw) as SavedIssue);
    } catch {
      // skip corrupt files
    }
  }
  return issues;
}

async function loadIssue(id: string): Promise<SavedIssue | null> {
  try {
    const raw = await readFile(join(ISSUES_DIR, `${id}.json`), "utf-8");
    return JSON.parse(raw) as SavedIssue;
  } catch {
    return null;
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

async function handleRequest(req: IncomingMessage, res: ServerResponse): Promise<void> {
  const url = req.url || "/";

  // API: list issues
  if (url === "/api/issues") {
    const issues = await loadAllIssues();
    const summaries = issues
      .sort((a, b) => new Date(b.issue.lastSeen).getTime() - new Date(a.issue.lastSeen).getTime())
      .map((s) => {
        const i = s.issue;
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

  // API: single mother issue
  const apiMotherMatch = url.match(/^\/api\/mother-issues\/([a-f0-9]+)$/);
  if (apiMotherMatch) {
    const mi = await loadMotherIssueFromDisk(apiMotherMatch[1]);
    if (!mi) return json(res, { error: "Not found" }, 404);
    return json(res, mi);
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

export function startServer(port: number): void {
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
