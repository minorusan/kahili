import "dotenv/config";
import { incrementBuild } from "./build.js";
import { ensureKahu } from "./kahu-manager.js";
import { startServer } from "./server.js";
import { log } from "./logger.js";

const port = parseInt(process.env.KAHILI_PORT || "3401", 10);

// 1. Banner
log.info("╔═══════════════════════════════════════╗");
log.info("║        kahili — Process Manager       ║");
log.info("╠═══════════════════════════════════════╣");

// 2. Increment build
const buildInfo = incrementBuild();
log.info(`║  Build:    ${String(buildInfo.build).padEnd(26)}║`);
log.info(`║  Port:     ${String(port).padEnd(26)}║`);
log.info("╚═══════════════════════════════════════╝");

// 3. Ensure kahu is running with current build
const kahuPid = await ensureKahu(buildInfo.build);
log.info(`[kahili] Kahu running at PID ${kahuPid}`);

// 4. Start HTTP server
startServer(port);
