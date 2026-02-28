import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { readBuild } from "./build.js";
import { readPidFile } from "./kahu-manager.js";
import { applyKahuSettings, readKahuSettings, type KahuSettings } from "./settings.js";
import { startInvestigation, getCurrentInvestigation, cancelInvestigation } from "./investigator.js";
import { attachWebSocket } from "./websocket.js";

const startTime = Date.now();

function json(res: ServerResponse, data: unknown, status = 200): void {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(data, null, 2));
}

function readBody(req: IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    req.on("data", (chunk: Buffer) => chunks.push(chunk));
    req.on("end", () => resolve(Buffer.concat(chunks).toString()));
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

async function handleRequest(req: IncomingMessage, res: ServerResponse): Promise<void> {
  // GET / or GET /api/status
  if (req.method === "GET" && (req.url === "/" || req.url === "/api/status")) {
    return json(res, statusPayload());
  }

  // GET /api/kahu-settings — read current settings
  if (req.method === "GET" && req.url === "/api/kahu-settings") {
    return json(res, readKahuSettings());
  }

  // POST /api/kahu-settings — apply new settings
  if (req.method === "POST" && req.url === "/api/kahu-settings") {
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
      console.error("[kahili] Failed to apply settings:", err);
      return json(
        res,
        { error: "failed to apply settings", detail: String(err) },
        500
      );
    }
  }

  // GET /api/investigate — current investigation status
  if (req.method === "GET" && req.url === "/api/investigate") {
    const inv = getCurrentInvestigation();
    if (!inv) {
      return json(res, { active: false });
    }
    return json(res, { active: inv.status === "running", investigation: inv });
  }

  // POST /api/investigate — start investigation
  if (req.method === "POST" && req.url === "/api/investigate") {
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

  // DELETE /api/investigate — cancel current investigation
  if (req.method === "DELETE" && req.url === "/api/investigate") {
    const cancelled = cancelInvestigation();
    return json(res, { ok: cancelled });
  }

  json(res, { error: "not found" }, 404);
}

export function startServer(port: number): void {
  const server = createServer((req, res) => {
    handleRequest(req, res).catch((err) => {
      console.error("[kahili] HTTP handler error:", err);
      if (!res.headersSent) {
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "internal server error" }));
      }
    });
  });

  attachWebSocket(server);

  server.listen(port, () => {
    console.log(`[kahili] HTTP server listening on http://localhost:${port}`);
  });
}
