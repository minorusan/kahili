import "dotenv/config";
import { incrementBuild } from "./build.js";
import { ensureKahu } from "./kahu-manager.js";
import { startServer } from "./server.js";

const port = parseInt(process.env.KAHILI_PORT || "3400", 10);

// 1. Banner
console.log("╔═══════════════════════════════════════╗");
console.log("║        kahili — Process Manager       ║");
console.log("╠═══════════════════════════════════════╣");

// 2. Increment build
const buildInfo = incrementBuild();
console.log(`║  Build:    ${String(buildInfo.build).padEnd(26)}║`);
console.log(`║  Port:     ${String(port).padEnd(26)}║`);
console.log("╚═══════════════════════════════════════╝");

// 3. Ensure kahu is running with current build
const kahuPid = await ensureKahu(buildInfo.build);
console.log(`[kahili] Kahu running at PID ${kahuPid}`);

// 4. Start HTTP server
startServer(port);
