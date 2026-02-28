import { type Server as HttpServer, type IncomingMessage } from "node:http";
import { WebSocketServer, WebSocket } from "ws";

let wss: WebSocketServer | null = null;

export function attachWebSocket(server: HttpServer): void {
  wss = new WebSocketServer({ server });

  wss.on("connection", (ws: WebSocket, req: IncomingMessage) => {
    console.log(`[kahili:ws] Client connected from ${req.socket.remoteAddress}`);
    ws.on("close", () => {
      console.log("[kahili:ws] Client disconnected");
    });
  });

  console.log("[kahili:ws] WebSocket server attached");
}

export function broadcast(type: string, data: unknown): void {
  if (!wss) return;
  const message = JSON.stringify({ type, data });
  for (const client of wss.clients) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(message);
    }
  }
}
