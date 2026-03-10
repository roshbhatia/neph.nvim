import * as http from "node:http";
import * as crypto from "node:crypto";
import { debug as log } from "../../lib/log";

export interface JsonRpcRequest {
  jsonrpc: "2.0";
  id?: string | number;
  method: string;
  params?: Record<string, unknown>;
}

export interface JsonRpcResponse {
  jsonrpc: "2.0";
  id: string | number | null;
  result?: unknown;
  error?: { code: number; message: string; data?: unknown };
}

export type ToolHandler = (
  params: Record<string, unknown>
) => Promise<{ content?: { type: string; text: string }[]; isError?: boolean }>;

export type NotificationHandler = (
  params: Record<string, unknown>
) => Promise<void>;

export interface McpServerOptions {
  authToken: string;
  tools: Record<string, { description: string; inputSchema: Record<string, unknown>; handler: ToolHandler }>;
  notifications?: Record<string, NotificationHandler>;
}

export class McpServer {
  private server: http.Server;
  private authToken: string;
  private tools: McpServerOptions["tools"];
  private notifications: Record<string, NotificationHandler>;
  private port = 0;

  constructor(options: McpServerOptions) {
    this.authToken = options.authToken;
    this.tools = options.tools;
    this.notifications = options.notifications ?? {};
    this.server = http.createServer((req, res) => this.handleRequest(req, res));
  }

  async start(): Promise<number> {
    return new Promise((resolve) => {
      this.server.listen(0, "127.0.0.1", () => {
        const addr = this.server.address();
        if (addr && typeof addr === "object") {
          this.port = addr.port;
          log("mcp-server", `listening on 127.0.0.1:${this.port}`);
          resolve(this.port);
        }
      });
    });
  }

  getPort(): number {
    return this.port;
  }

  async stop(): Promise<void> {
    return new Promise((resolve) => {
      this.server.close(() => resolve());
    });
  }

  private async handleRequest(req: http.IncomingMessage, res: http.ServerResponse): Promise<void> {
    if (req.method !== "POST") {
      res.writeHead(405, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Method not allowed" }));
      return;
    }

    // Auth check
    const authHeader = req.headers.authorization;
    if (!authHeader || authHeader !== `Bearer ${this.authToken}`) {
      res.writeHead(401, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Unauthorized" }));
      return;
    }

    // Read body (1MB limit, tracked in bytes)
    const MAX_BODY = 1_048_576;
    let body = "";
    let bodyBytes = 0;
    for await (const chunk of req) {
      bodyBytes += Buffer.isBuffer(chunk) ? chunk.length : Buffer.byteLength(chunk as string);
      body += chunk;
      if (bodyBytes > MAX_BODY) {
        req.destroy();
        res.writeHead(413, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Payload Too Large" }));
        return;
      }
    }

    let rpc: JsonRpcRequest;
    try {
      rpc = JSON.parse(body) as JsonRpcRequest;
    } catch {
      this.sendJsonRpc(res, null, undefined, { code: -32700, message: "Parse error" });
      return;
    }

    if (!rpc.jsonrpc || rpc.jsonrpc !== "2.0" || !rpc.method) {
      this.sendJsonRpc(res, rpc.id ?? null, undefined, { code: -32600, message: "Invalid Request" });
      return;
    }

    log("mcp-server", `request: ${rpc.method} (id=${rpc.id ?? "notification"})`);
    await this.routeRequest(rpc, res);
  }

  private async routeRequest(rpc: JsonRpcRequest, res: http.ServerResponse): Promise<void> {
    const params = rpc.params ?? {};

    // MCP initialize
    if (rpc.method === "initialize") {
      this.sendJsonRpc(res, rpc.id ?? null, {
        protocolVersion: "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: { name: "neph-gemini-companion", version: "1.0.0" },
      });
      return;
    }

    // MCP tools/list
    if (rpc.method === "tools/list") {
      const toolList = Object.entries(this.tools).map(([name, def]) => ({
        name,
        description: def.description,
        inputSchema: def.inputSchema,
      }));
      this.sendJsonRpc(res, rpc.id ?? null, { tools: toolList });
      return;
    }

    // MCP tools/call
    if (rpc.method === "tools/call") {
      const toolName = params.name as string;
      const toolArgs = (params.arguments ?? {}) as Record<string, unknown>;
      const tool = this.tools[toolName];
      if (!tool) {
        this.sendJsonRpc(res, rpc.id ?? null, undefined, {
          code: -32601,
          message: `Unknown tool: ${toolName}`,
        });
        return;
      }
      try {
        const result = await tool.handler(toolArgs);
        this.sendJsonRpc(res, rpc.id ?? null, result);
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        this.sendJsonRpc(res, rpc.id ?? null, undefined, {
          code: -32603,
          message: `Tool error: ${message}`,
        });
      }
      return;
    }

    // MCP notifications (no response expected for true notifications, but HTTP needs a response)
    const notifHandler = this.notifications[rpc.method];
    if (notifHandler) {
      try {
        await notifHandler(params);
      } catch (err) {
        log("mcp-server", `notification handler error: ${err}`);
      }
      // Notifications: send empty OK if it has an id, or just 200
      if (rpc.id !== undefined) {
        this.sendJsonRpc(res, rpc.id, {});
      } else {
        res.writeHead(200);
        res.end();
      }
      return;
    }

    this.sendJsonRpc(res, rpc.id ?? null, undefined, {
      code: -32601,
      message: `Method not found: ${rpc.method}`,
    });
  }

  private sendJsonRpc(
    res: http.ServerResponse,
    id: string | number | null,
    result?: unknown,
    error?: { code: number; message: string; data?: unknown }
  ): void {
    const response: JsonRpcResponse = { jsonrpc: "2.0", id };
    if (error) {
      response.error = error;
    } else {
      response.result = result;
    }
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify(response));
  }
}

export function generateAuthToken(): string {
  return crypto.randomUUID();
}
