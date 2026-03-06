import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { execFile } from "node:child_process";
import { readFile, stat, readdir, unlink } from "node:fs/promises";
import path from "node:path";
const { join, extname, resolve } = path;
import { readBuild } from "./build.js";
import { readPidFile } from "./kahu-manager.js";
import { applyKahuSettings, readKahuSettings, type KahuSettings } from "./settings.js";
import { startInvestigation, getCurrentInvestigation, cancelInvestigation } from "./investigator.js";
import { startRuleGeneration, getCurrentRuleGeneration, cancelRuleGeneration, deleteRule } from "./rule-generator.js";
import { startHelpAgent, getCurrentHelpAgent, cancelHelpAgent, listHelpQuestions, getHelpAnswer } from "./help-agent.js";
import { startDevelopAgent, getCurrentDevelopAgent, cancelDevelopAgent, listDevelopRequests, getDevelopDetail } from "./develop-agent.js";
import { listPrompts, getPromptTemplate, savePromptTemplate } from "./prompt-store.js";
import { attachWebSocket } from "./websocket.js";
import { log } from "./logger.js";

// Flutter web build directory (two levels up from dist/ to repo root, then client/build/web)
const WEB_ROOT = join(import.meta.dirname!, "..", "..", "..", "client", "build", "web");

/** Cache-bust token derived from build output mtimes. Computed once at startup. */
let cacheBustToken = Date.now().toString(36);

/**
 * Preloader HTML: shows icon + name, nukes all caches, then boots Flutter.
 * This page is generated server-side so it's never stale.
 */
function buildPreloaderHtml(): string {
  const v = cacheBustToken;
  return `<!DOCTYPE html>
<html>
<head>
  <base href="/">
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Kahili</title>
  <link rel="icon" type="image/png" href="favicon.png"/>
  <style>
    *{margin:0;padding:0;box-sizing:border-box}

    body {
      background: #06060A;
      display: flex;
      align-items: center;
      justify-content: center;
      height: 100vh;
      overflow: hidden;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    }

    /* ── ambient background glow ── */
    .ambient {
      position: fixed;
      inset: 0;
      z-index: 0;
      background:
        radial-gradient(ellipse 600px 400px at 50% 45%, rgba(255,109,0,0.06) 0%, transparent 70%),
        radial-gradient(ellipse 300px 300px at 52% 40%, rgba(0,229,255,0.03) 0%, transparent 60%);
      animation: ambientPulse 4s ease-in-out infinite;
    }
    @keyframes ambientPulse {
      0%, 100% { opacity: 0.6; transform: scale(1); }
      50%      { opacity: 1;   transform: scale(1.05); }
    }

    /* ── main container ── */
    #preloader {
      position: fixed;
      inset: 0;
      z-index: 9999;
      background: #06060A;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      gap: 20px;
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 20px;
      opacity: 0;
      transform: translateY(12px) scale(0.96);
      animation: enterPreloader 0.8s cubic-bezier(0.22, 1, 0.36, 1) 0.1s forwards;
    }
    @keyframes enterPreloader {
      to { opacity: 1; transform: translateY(0) scale(1); }
    }
    #preloader.fade {
      animation: exitPreloader 0.5s cubic-bezier(0.55, 0, 1, 0.45) forwards;
    }
    @keyframes exitPreloader {
      to { opacity: 0; transform: translateY(-10px) scale(1.02); }
    }

    /* ── icon wrapper with glow rings ── */
    .icon-wrap {
      position: relative;
      width: 72px;
      height: 128px;
    }

    /* outer glow */
    .icon-wrap::before {
      content: '';
      position: absolute;
      inset: -24px -30px;
      border-radius: 50%;
      background: radial-gradient(ellipse, rgba(255,109,0,0.15) 0%, rgba(255,109,0,0) 70%);
      animation: glowPulse 3s ease-in-out infinite;
    }

    /* inner cyan glow */
    .icon-wrap::after {
      content: '';
      position: absolute;
      inset: -10px -16px;
      border-radius: 50%;
      background: radial-gradient(ellipse, rgba(0,229,255,0.08) 0%, transparent 65%);
      animation: glowPulse 3s ease-in-out 1.5s infinite;
    }

    @keyframes glowPulse {
      0%, 100% { transform: scale(1);    opacity: 0.5; }
      50%      { transform: scale(1.15); opacity: 1; }
    }

    .icon-wrap img {
      position: relative;
      width: 100%;
      height: 100%;
      object-fit: contain;
      z-index: 1;
      filter: drop-shadow(0 0 20px rgba(255,109,0,0.3))
              drop-shadow(0 0 40px rgba(255,109,0,0.1));
      animation: iconBreathe 3s ease-in-out infinite;
    }
    @keyframes iconBreathe {
      0%, 100% { transform: scale(1);     filter: drop-shadow(0 0 20px rgba(255,109,0,0.3)) drop-shadow(0 0 40px rgba(255,109,0,0.1)); }
      50%      { transform: scale(1.04);   filter: drop-shadow(0 0 28px rgba(255,109,0,0.45)) drop-shadow(0 0 50px rgba(255,109,0,0.15)); }
    }

    /* ── app name ── */
    .name {
      font-size: 24px;
      font-weight: 700;
      letter-spacing: 3px;
      text-transform: uppercase;
      background: linear-gradient(135deg, #E8E8F0 0%, #FF9100 50%, #E8E8F0 100%);
      background-size: 200% auto;
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      background-clip: text;
      animation: shimmerText 4s ease-in-out infinite;
    }
    @keyframes shimmerText {
      0%, 100% { background-position: 0% center; }
      50%      { background-position: 100% center; }
    }

    /* ── loading bar ── */
    .loader {
      width: 120px;
      height: 2px;
      background: rgba(255,255,255,0.06);
      border-radius: 1px;
      overflow: hidden;
      margin-top: 4px;
    }
    .loader-bar {
      height: 100%;
      width: 40%;
      border-radius: 1px;
      background: linear-gradient(90deg, transparent, #FF6D00, #00E5FF, transparent);
      animation: loaderSlide 1.6s ease-in-out infinite;
    }
    @keyframes loaderSlide {
      0%   { transform: translateX(-120%); }
      100% { transform: translateX(350%); }
    }
  </style>
</head>
<body>
  <div class="ambient"></div>
  <div id="preloader">
    <div class="icon-wrap">
      <img src="assets/assets/kahili_feather_icon_cropped.png" alt="">
    </div>
    <div class="name">Kahili</div>
    <div class="loader"><div class="loader-bar"></div></div>
  </div>
  <script>
    (async function() {
      if ('serviceWorker' in navigator) {
        var regs = await navigator.serviceWorker.getRegistrations();
        for (var r of regs) await r.unregister();
      }
      if ('caches' in window) {
        var names = await caches.keys();
        for (var n of names) await caches.delete(n);
      }

      // Start loading Flutter immediately
      var s = document.createElement('script');
      s.src = 'flutter_bootstrap.js?v=${v}';
      s.async = true;
      document.head.appendChild(s);

      // Keep preloader visible until Flutter actually renders
      var observer = new MutationObserver(function() {
        if (document.querySelector('flutter-view') || document.querySelector('flt-glass-pane')) {
          observer.disconnect();
          // Brief delay to let Flutter paint its first frame
          setTimeout(function() {
            document.getElementById('preloader').classList.add('fade');
            setTimeout(function() {
              var el = document.getElementById('preloader');
              if (el) el.style.display = 'none';
              var amb = document.querySelector('.ambient');
              if (amb) amb.style.display = 'none';
            }, 500);
          }, 300);
        }
      });
      observer.observe(document.body, { childList: true, subtree: true });
    })();
  </script>
</body>
</html>`;
}

const MIME_TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "application/javascript",
  ".css": "text/css",
  ".json": "application/json",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".ttf": "font/ttf",
  ".otf": "font/otf",
  ".wasm": "application/wasm",
};

const startTime = Date.now();

function json(res: ServerResponse, data: unknown, status = 200): void {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(data, null, 2));
}

const MAX_BODY = 1024 * 1024; // 1MB

function readBody(req: IncomingMessage): Promise<string> {
  return new Promise((resolveBody, reject) => {
    const chunks: Buffer[] = [];
    let totalSize = 0;
    req.on("data", (chunk: Buffer) => {
      totalSize += chunk.length;
      if (totalSize > MAX_BODY) {
        reject(new Error("body too large"));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolveBody(Buffer.concat(chunks).toString()));
    req.on("error", reject);
  });
}

function statusPayload() {
  const buildInfo = readBuild();
  const pidInfo = readPidFile();

  return {
    name: "kahili",
    build: buildInfo.build,
    kahuPid: pidInfo?.pid ?? null,
    kahuBuild: pidInfo?.build ?? null,
    uptime: Math.floor((Date.now() - startTime) / 1000),
  };
}

function gitExec(args: string[], cwd: string): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile("git", args, { cwd, maxBuffer: 10 * 1024 * 1024 }, (err, stdout, stderr) => {
      // git fetch writes progress to stderr even on success
      if (err && args[0] !== "fetch") {
        reject(new Error(`git ${args[0]} failed: ${stderr || err.message}`));
        return;
      }
      resolve(stdout);
    });
  });
}

async function serveStatic(res: ServerResponse, urlPath: string): Promise<boolean> {
  // Strip query parameters before resolving file path
  const pathOnly = urlPath.split("?")[0];

  // Block service-worker and manifest requests — never serve these
  const blocked = ["/flutter_service_worker.js", "/manifest.json"];
  if (blocked.includes(pathOnly)) {
    res.writeHead(404, { "Content-Type": "text/plain" });
    res.end("Not found");
    return true;
  }

  // Prevent path traversal with proper resolution
  const resolved = resolve(WEB_ROOT, "." + pathOnly);
  if (!resolved.startsWith(WEB_ROOT)) {
    res.writeHead(404, { "Content-Type": "text/plain" });
    res.end("Not found");
    return true;
  }

  let filePath = pathOnly === "/" ? join(WEB_ROOT, "index.html") : resolved;

  try {
    const s = await stat(filePath);
    if (s.isDirectory()) filePath = join(filePath, "index.html");
  } catch {
    // File doesn't exist — serve index.html for SPA routing
    filePath = join(WEB_ROOT, "index.html");
  }

  try {
    let data = await readFile(filePath);
    const ext = extname(filePath);
    const contentType = MIME_TYPES[ext] || "application/octet-stream";
    const headers: Record<string, string> = {
      "Content-Type": contentType,
      "Cache-Control": "no-cache, no-store, must-revalidate",
    };

    // index.html: serve preloader that nukes caches then boots Flutter
    if (filePath.endsWith("index.html")) {
      headers["Clear-Site-Data"] = '"cache"';
      data = Buffer.from(buildPreloaderHtml(), "utf-8");
    }

    // Inject cache-bust token into flutter_bootstrap.js so main.dart.js URL changes too
    if (filePath.endsWith("flutter_bootstrap.js")) {
      let js = data.toString("utf-8");
      js = js.replace(
        '"main.dart.js"',
        `"main.dart.js?v=${cacheBustToken}"`
      );
      data = Buffer.from(js, "utf-8");
    }

    // Bust font/asset URLs inside FontManifest.json so fonts always reload
    if (filePath.endsWith("FontManifest.json")) {
      let manifest = data.toString("utf-8");
      manifest = manifest.replace(
        /("asset"\s*:\s*"[^"]+)/g,
        `$1?v=${cacheBustToken}`
      );
      data = Buffer.from(manifest, "utf-8");
    }

    // Bust asset URLs inside AssetManifest files
    if (filePath.includes("AssetManifest")) {
      let manifest = data.toString("utf-8");
      // For .json variant, bust URL strings
      if (filePath.endsWith(".json")) {
        manifest = manifest.replace(
          /("assets\/[^"]+)/g,
          `$1?v=${cacheBustToken}`
        );
      }
      data = Buffer.from(manifest, "utf-8");
    }

    res.writeHead(200, headers);
    res.end(data);
    return true;
  } catch {
    return false;
  }
}

async function handleRequest(req: IncomingMessage, res: ServerResponse): Promise<void> {
  const url = req.url || "/";

  // API routes
  if (url === "/api/status") {
    return json(res, statusPayload());
  }

  // POST /api/client-log — receive client-side error logs
  if (req.method === "POST" && url === "/api/client-log") {
    try {
      const raw = await readBody(req);
      const body = JSON.parse(raw);
      const level = body.level || "error";
      const msg = body.message || "";
      const stack = body.stackTrace || "";
      if (level === "error") {
        log.error(`[CLIENT] ${msg}`);
        if (stack) log.error(`[CLIENT:STACK] ${stack}`);
      } else {
        log.info(`[CLIENT:${level}] ${msg}`);
      }
    } catch {
      // don't fail on malformed logs
    }
    return json(res, { ok: true });
  }

  // GET /api/kahu-settings — read current settings
  if (req.method === "GET" && url === "/api/kahu-settings") {
    return json(res, readKahuSettings());
  }

  // POST /api/kahu-settings — apply new settings
  if (req.method === "POST" && url === "/api/kahu-settings") {
    let body: KahuSettings;
    try {
      const raw = await readBody(req);
      body = JSON.parse(raw) as KahuSettings;
    } catch {
      return json(res, { error: "invalid JSON body" }, 400);
    }

    try {
      const result = await applyKahuSettings(body);
      return json(res, {
        ok: true,
        envWritten: result.env,
        motherIssuesBackfilled: result.backfilled,
        kahuPid: result.kahuPid,
      });
    } catch (err) {
      log.error("[kahili] Failed to apply settings:", err);
      return json(
        res,
        { error: "failed to apply settings", detail: String(err) },
        500
      );
    }
  }

  // GET /api/investigate — current investigation status
  if (req.method === "GET" && url === "/api/investigate") {
    const inv = getCurrentInvestigation();
    if (!inv) {
      return json(res, { active: false });
    }
    return json(res, { active: inv.status === "running", investigation: inv });
  }

  // POST /api/investigate — start investigation
  if (req.method === "POST" && url === "/api/investigate") {
    let body: { motherIssueId?: string; branch?: string; additionalPrompt?: string };
    try {
      const raw = await readBody(req);
      body = JSON.parse(raw);
    } catch {
      return json(res, { error: "invalid JSON body" }, 400);
    }

    if (!body.motherIssueId) {
      return json(res, { error: "motherIssueId is required" }, 400);
    }

    try {
      const inv = await startInvestigation(
        body.motherIssueId,
        body.branch,
        body.additionalPrompt
      );
      return json(res, { ok: true, investigation: inv });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      const status = msg.includes("already running") ? 409 : 500;
      return json(res, { error: msg }, status);
    }
  }

  // GET /api/repo-info — fetch and return release branches/tags
  if (req.method === "GET" && url === "/api/repo-info") {
    const settings = readKahuSettings();
    const repoPath = settings.REPO_PATH;
    if (!repoPath) {
      return json(res, { error: "REPO_PATH not configured" }, 400);
    }

    try {
      await gitExec(["fetch", "--all", "--tags"], repoPath);

      const [branchOut, tagOut] = await Promise.all([
        gitExec(["branch", "-r", "--list", "*release*", "--sort=-committerdate"], repoPath),
        gitExec(["tag", "--sort=-creatordate"], repoPath),
      ]);

      const branches = branchOut.split("\n").map((b) => b.trim()).filter(Boolean).slice(0, 20);
      const tags = tagOut.split("\n").map((t) => t.trim()).filter(Boolean).slice(0, 20);

      return json(res, { branches, tags });
    } catch (err) {
      log.error("[kahili] repo-info failed:", err);
      return json(res, { error: "git operation failed", detail: String(err) }, 500);
    }
  }

  // DELETE /api/investigate — cancel current investigation
  if (req.method === "DELETE" && url === "/api/investigate") {
    const cancelled = cancelInvestigation();
    return json(res, { ok: cancelled });
  }

  // GET /api/reports/status — list which mother issues have reports
  if (req.method === "GET" && url === "/api/reports/status") {
    const investigationsDir = join(import.meta.dirname!, "..", "..", "docs", "investigations");
    try {
      const files = await readdir(investigationsDir);
      const ids = files
        .filter((f) => f.endsWith(".md"))
        .map((f) => f.replace(/\.md$/, ""));
      return json(res, { investigated: ids });
    } catch {
      return json(res, { investigated: [] });
    }
  }

  // GET /api/report/:motherIssueId — get investigation report
  const reportMatch = url.match(/^\/api\/report\/([a-f0-9]+)$/);
  if (req.method === "GET" && reportMatch) {
    const issueId = reportMatch[1];
    const reportPath = join(import.meta.dirname!, "..", "..", "docs", "investigations", `${issueId}.md`);
    try {
      const content = await readFile(reportPath, "utf-8");
      return json(res, { exists: true, motherIssueId: issueId, report: content });
    } catch {
      return json(res, { exists: false, motherIssueId: issueId });
    }
  }

  // GET /api/generate-rule — current rule generation status
  if (req.method === "GET" && url === "/api/generate-rule") {
    const gen = getCurrentRuleGeneration();
    if (!gen) {
      return json(res, { active: false });
    }
    return json(res, { active: gen.status === "running", generation: gen });
  }

  // POST /api/generate-rule — start rule generation
  if (req.method === "POST" && url === "/api/generate-rule") {
    let body: { prompt?: string };
    try {
      const raw = await readBody(req);
      body = JSON.parse(raw);
    } catch {
      return json(res, { error: "invalid JSON body" }, 400);
    }

    if (!body.prompt) {
      return json(res, { error: "prompt is required" }, 400);
    }

    try {
      const gen = await startRuleGeneration(body.prompt);
      return json(res, { ok: true, generation: gen });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      const status = msg.includes("already running") ? 409 : 500;
      return json(res, { error: msg }, status);
    }
  }

  // DELETE /api/generate-rule — cancel rule generation
  if (req.method === "DELETE" && url === "/api/generate-rule") {
    const cancelled = cancelRuleGeneration();
    return json(res, { ok: cancelled });
  }

  // POST /api/regenerate-rule — delete old rule + mother issues, then generate new rule
  if (req.method === "POST" && url === "/api/regenerate-rule") {
    let body: { ruleName?: string; prompt?: string };
    try {
      const raw = await readBody(req);
      body = JSON.parse(raw);
    } catch {
      return json(res, { error: "invalid JSON body" }, 400);
    }

    if (!body.ruleName || !body.prompt) {
      return json(res, { error: "ruleName and prompt are required" }, 400);
    }

    try {
      // 1. Delete old rule and its mother issues
      const deleteResult = deleteRule(body.ruleName);
      log.info(`[kahili] Deleted rule ${body.ruleName}: ${deleteResult.filesRemoved} mother issues removed`);

      // 2. Start new rule generation
      const gen = await startRuleGeneration(body.prompt);
      return json(res, { ok: true, deleted: deleteResult, generation: gen });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      const status = msg.includes("already running") ? 409 : 500;
      return json(res, { error: msg }, status);
    }
  }

  // GET /api/daily-reports — list available daily report dates
  if (req.method === "GET" && url === "/api/daily-reports") {
    const reportsDir = join(import.meta.dirname!, "..", "..", "kahu", "data", "reports");
    try {
      const files = await readdir(reportsDir);
      const dates = files
        .filter((f) => f.endsWith(".md"))
        .map((f) => f.replace(/\.md$/, ""))
        .sort()
        .reverse();
      return json(res, { dates });
    } catch {
      return json(res, { dates: [] });
    }
  }

  // GET /api/daily-reports/:date — get a specific day's report
  const dailyMatch = url.match(/^\/api\/daily-reports\/(\d{4}-\d{2}-\d{2})$/);
  if (req.method === "GET" && dailyMatch) {
    const date = dailyMatch[1];
    const reportPath = join(import.meta.dirname!, "..", "..", "kahu", "data", "reports", `${date}.md`);
    try {
      const content = await readFile(reportPath, "utf-8");
      return json(res, { exists: true, date, report: content });
    } catch {
      return json(res, { exists: false, date });
    }
  }

  // GET /api/help-agent — current help agent status
  if (req.method === "GET" && url === "/api/help-agent") {
    const agent = getCurrentHelpAgent();
    if (!agent) {
      return json(res, { active: false });
    }
    return json(res, { active: agent.status === "running", agent });
  }

  // POST /api/help-agent — start help agent
  if (req.method === "POST" && url === "/api/help-agent") {
    let body: { question?: string };
    try {
      const raw = await readBody(req);
      body = JSON.parse(raw);
    } catch {
      return json(res, { error: "invalid JSON body" }, 400);
    }

    if (!body.question) {
      return json(res, { error: "question is required" }, 400);
    }

    try {
      const agent = await startHelpAgent(body.question);
      return json(res, { ok: true, agent });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      const status = msg.includes("already being processed") ? 409 : 500;
      return json(res, { error: msg }, status);
    }
  }

  // DELETE /api/help-agent — cancel help agent
  if (req.method === "DELETE" && url === "/api/help-agent") {
    const cancelled = cancelHelpAgent();
    return json(res, { ok: cancelled });
  }

  // GET /api/help-questions — list all help questions
  if (req.method === "GET" && url === "/api/help-questions") {
    return json(res, listHelpQuestions());
  }

  // GET /api/help-questions/:id — get a specific question with answer
  const helpMatch = url.match(/^\/api\/help-questions\/([a-z0-9]+)$/);
  if (req.method === "GET" && helpMatch) {
    const answer = getHelpAnswer(helpMatch[1]);
    if (!answer) {
      return json(res, { error: "not found" }, 404);
    }
    return json(res, answer);
  }

  // GET /api/develop-agent — current develop agent status
  if (req.method === "GET" && url === "/api/develop-agent") {
    const agent = getCurrentDevelopAgent();
    if (!agent) {
      return json(res, { active: false });
    }
    return json(res, { active: agent.status === "running", agent });
  }

  // POST /api/develop-agent — start develop agent
  if (req.method === "POST" && url === "/api/develop-agent") {
    let body: { request?: string };
    try {
      const raw = await readBody(req);
      body = JSON.parse(raw);
    } catch {
      return json(res, { error: "invalid JSON body" }, 400);
    }

    if (!body.request) {
      return json(res, { error: "request is required" }, 400);
    }

    try {
      const agent = await startDevelopAgent(body.request);
      return json(res, { ok: true, agent });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      const status = msg.includes("already being processed") ? 409 : 500;
      return json(res, { error: msg }, status);
    }
  }

  // DELETE /api/develop-agent — cancel develop agent
  if (req.method === "DELETE" && url === "/api/develop-agent") {
    const cancelled = cancelDevelopAgent();
    return json(res, { ok: cancelled });
  }

  // GET /api/develop-requests — list all develop requests
  if (req.method === "GET" && url === "/api/develop-requests") {
    return json(res, listDevelopRequests());
  }

  // GET /api/develop-requests/:id — get a specific request with report
  const developMatch = url.match(/^\/api\/develop-requests\/([a-z0-9]+)$/);
  if (req.method === "GET" && developMatch) {
    const detail = getDevelopDetail(developMatch[1]);
    if (!detail) {
      return json(res, { error: "not found" }, 404);
    }
    return json(res, detail);
  }

  // GET /api/prompts — list all agent prompts
  if (req.method === "GET" && url === "/api/prompts") {
    return json(res, listPrompts());
  }

  // GET /api/prompts/:name — get a specific prompt template
  const promptGetMatch = url.match(/^\/api\/prompts\/([a-z-]+)$/);
  if (req.method === "GET" && promptGetMatch) {
    const name = promptGetMatch[1];
    const template = getPromptTemplate(name);
    if (!template) {
      return json(res, { error: "not found" }, 404);
    }
    return json(res, { name, template });
  }

  // PUT /api/prompts/:name — save a customized prompt
  const promptPutMatch = url.match(/^\/api\/prompts\/([a-z-]+)$/);
  if (req.method === "PUT" && promptPutMatch) {
    let body: { template?: string };
    try {
      const raw = await readBody(req);
      body = JSON.parse(raw);
    } catch {
      return json(res, { error: "invalid JSON body" }, 400);
    }

    if (!body.template) {
      return json(res, { error: "template is required" }, 400);
    }

    savePromptTemplate(promptPutMatch[1], body.template);
    return json(res, { ok: true, name: promptPutMatch[1] });
  }

  // Proxy kahu API — /api/kahu/* → kahu:3456/api/*
  if (url.startsWith("/api/kahu/")) {
    const kahuPath = url.replace("/api/kahu/", "/api/");
    try {
      const fetchInit: RequestInit = { method: req.method };
      if (req.method === "POST" || req.method === "PUT") {
        fetchInit.headers = { "Content-Type": "application/json" };
        fetchInit.body = await readBody(req);
      }
      const kahuRes = await fetch(`http://localhost:3456${kahuPath}`, fetchInit);
      const body = await kahuRes.text();
      res.writeHead(kahuRes.status, { "Content-Type": kahuRes.headers.get("content-type") || "application/json" });
      res.end(body);
      return;
    } catch (err) {
      return json(res, { error: "kahu unavailable", detail: String(err) }, 502);
    }
  }

  // GET /clear — standalone cache-nuking page (bypasses service worker)
  if (req.method === "GET" && (url === "/clear" || url.startsWith("/clear?"))) {
    const clearHtml = `<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Clearing cache...</title></head>
<body style="font-family:sans-serif;text-align:center;padding:40px">
<h2>Clearing cache &amp; service workers...</h2>
<p id="status">Working...</p>
<script>
(async function() {
  const s = document.getElementById('status');
  try {
    if ('serviceWorker' in navigator) {
      const regs = await navigator.serviceWorker.getRegistrations();
      for (const r of regs) await r.unregister();
      s.textContent = 'Unregistered ' + regs.length + ' service worker(s). ';
    }
    if ('caches' in window) {
      const names = await caches.keys();
      for (const n of names) await caches.delete(n);
      s.textContent += 'Deleted ' + names.length + ' cache(s). ';
    }
    s.textContent += 'Redirecting...';
    setTimeout(function() { window.location.href = '/?t=' + Date.now(); }, 1000);
  } catch(e) {
    s.textContent = 'Error: ' + e.message;
  }
})();
</script></body></html>`;
    res.writeHead(200, {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-cache, no-store, must-revalidate",
      "Clear-Site-Data": "\"cache\", \"storage\"",
    });
    res.end(clearHtml);
    return;
  }

  // Non-API routes: serve Flutter web app
  if (req.method === "GET" && !url.startsWith("/api/")) {
    const served = await serveStatic(res, url);
    if (served) return;
  }

  json(res, { error: "not found" }, 404);
}

export async function startServer(port: number): Promise<void> {
  // Compute cache-bust token from Flutter build output mtime
  try {
    const mainJs = join(WEB_ROOT, "main.dart.js");
    const s = await stat(mainJs);
    cacheBustToken = s.mtimeMs.toString(36);
    log.info(`[kahili] Cache-bust token: ${cacheBustToken}`);
  } catch {
    log.warn("[kahili] Could not stat main.dart.js — using startup timestamp for cache-bust");
  }

  const server = createServer((req, res) => {
    handleRequest(req, res).catch((err) => {
      log.error("[kahili] HTTP handler error:", err);
      if (!res.headersSent) {
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "internal server error" }));
      }
    });
  });

  attachWebSocket(server);

  server.listen(port, () => {
    log.info(`[kahili] HTTP server listening on http://localhost:${port}`);
  });
}
