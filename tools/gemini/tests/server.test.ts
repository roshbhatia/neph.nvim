import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { McpServer, generateAuthToken } from "../src/server";

describe("McpServer", () => {
  let server: McpServer;
  let port: number;
  const token = generateAuthToken();

  beforeAll(async () => {
    server = new McpServer({
      authToken: token,
      tools: {
        echo: {
          description: "Echo tool",
          inputSchema: { type: "object", properties: { msg: { type: "string" } } },
          handler: async (params) => ({
            content: [{ type: "text", text: params.msg as string }],
          }),
        },
        fail: {
          description: "Failing tool",
          inputSchema: { type: "object", properties: {} },
          handler: async () => {
            throw new Error("intentional error");
          },
        },
      },
    });
    port = await server.start();
  });

  afterAll(async () => {
    await server.stop();
  });

  async function rpc(method: string, params: Record<string, unknown> = {}, id: number = 1): Promise<Response> {
    return fetch(`http://127.0.0.1:${port}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ jsonrpc: "2.0", id, method, params }),
    });
  }

  it("rejects missing auth token with 401", async () => {
    const res = await fetch(`http://127.0.0.1:${port}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "initialize" }),
    });
    expect(res.status).toBe(401);
  });

  it("rejects wrong auth token with 401", async () => {
    const res = await fetch(`http://127.0.0.1:${port}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: "Bearer wrong-token",
      },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "initialize" }),
    });
    expect(res.status).toBe(401);
  });

  it("handles initialize", async () => {
    const res = await rpc("initialize");
    const json = await res.json();
    expect(json.result.serverInfo.name).toBe("neph-gemini-companion");
    expect(json.result.capabilities.tools).toBeDefined();
  });

  it("lists tools", async () => {
    const res = await rpc("tools/list");
    const json = await res.json();
    expect(json.result.tools).toHaveLength(2);
    const names = json.result.tools.map((t: { name: string }) => t.name);
    expect(names).toContain("echo");
    expect(names).toContain("fail");
  });

  it("calls a tool successfully", async () => {
    const res = await rpc("tools/call", { name: "echo", arguments: { msg: "hello" } });
    const json = await res.json();
    expect(json.result.content).toEqual([{ type: "text", text: "hello" }]);
  });

  it("returns error for unknown tool", async () => {
    const res = await rpc("tools/call", { name: "nonexistent", arguments: {} });
    const json = await res.json();
    expect(json.error.code).toBe(-32601);
  });

  it("returns isError for throwing tool", async () => {
    const res = await rpc("tools/call", { name: "fail", arguments: {} });
    const json = await res.json();
    expect(json.result.isError).toBe(true);
    expect(json.result.content[0].text).toContain("intentional error");
  });

  it("returns parse error for invalid JSON", async () => {
    const res = await fetch(`http://127.0.0.1:${port}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: "not json",
    });
    const json = await res.json();
    expect(json.error.code).toBe(-32700);
  });

  it("returns invalid request for missing jsonrpc field", async () => {
    const res = await fetch(`http://127.0.0.1:${port}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ method: "initialize" }),
    });
    const json = await res.json();
    expect(json.error.code).toBe(-32600);
  });

  it("rejects non-POST methods", async () => {
    const res = await fetch(`http://127.0.0.1:${port}`, {
      method: "GET",
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(res.status).toBe(405);
  });
});
