import { attach, type NeovimClient } from "neovim";
import process from "node:process";
import { debug as log } from "./log";

export interface ReviewEnvelope {
  schema: "review/v1";
  decision: "accept" | "reject" | "partial";
  content: string;
  hunks: { index: number; decision: "accept" | "reject"; reason?: string }[];
  reason?: string;
}

const RPC_CALL = 'return require("neph.rpc").request(...)';

export class NephClient {
  private client: NeovimClient | null = null;
  private agentName: string | null = null;
  private channelId: number | null = null;
  private socketPath: string | null = null;
  private promptCallback: ((text: string) => void) | null = null;
  private reconnecting = false;
  private disconnected = false;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private reconnectDelay = 100;
  private static readonly MAX_RECONNECT_DELAY = 5000;

  async connect(socketPath?: string): Promise<void> {
    const path = socketPath || process.env.NVIM_SOCKET_PATH;
    if (!path) {
      throw new Error("No socket path: set NVIM_SOCKET_PATH or pass socketPath");
    }
    this.socketPath = path;
    this.disconnected = false;

    this.client = attach({ socket: path });
    const apiInfo = await this.client.request("nvim_get_api_info");
    this.channelId = (apiInfo as [number, unknown])[0];
    log("neph-client", `connected to ${path} (channel=${this.channelId})`);

    // Listen for prompt notifications
    this.client.on("notification", (method: string, args: unknown[]) => {
      if (method === "neph:prompt" && this.promptCallback) {
        const text = args[0];
        log("neph-client", `received prompt (len=${String(text).length})`);
        this.promptCallback(typeof text === "string" ? text : String(text));
      }
    });

    // Handle disconnect
    this.client.on("disconnect", () => {
      log("neph-client", "socket disconnected");
      this.client = null;
      this.channelId = null;
      if (!this.disconnected) {
        this._scheduleReconnect();
      }
    });
  }

  async register(agentName: string): Promise<void> {
    this.agentName = agentName;
    if (!this.client || this.channelId === null) {
      throw new Error("Not connected");
    }
    const result = await this.client.executeLua(RPC_CALL, [
      "bus.register",
      { name: agentName, channel: this.channelId },
    ]);
    const res = result as { ok: boolean; result?: { ok: boolean; error?: string } };
    if (res?.ok && res?.result?.ok) {
      log("neph-client", `registered as ${agentName}`);
    } else {
      const err = res?.result?.error || "registration failed";
      throw new Error(`Registration failed: ${err}`);
    }
  }

  onPrompt(callback: (text: string) => void): void {
    this.promptCallback = callback;
  }

  async setStatus(name: string, value: string): Promise<void> {
    if (!this.client) return;
    await this.client.executeLua(RPC_CALL, ["status.set", { name, value }]);
  }

  async unsetStatus(name: string): Promise<void> {
    if (!this.client) return;
    await this.client.executeLua(RPC_CALL, ["status.unset", { name }]);
  }

  async review(filePath: string, content: string): Promise<ReviewEnvelope> {
    if (!this.client) {
      return {
        schema: "review/v1",
        decision: "reject",
        content: "",
        hunks: [],
        reason: "Not connected to Neovim",
      };
    }
    try {
      const result = await this.client.executeLua(RPC_CALL, [
        "review.open",
        { file: filePath, content },
      ]);
      const res = result as { ok: boolean; result?: ReviewEnvelope };
      if (res?.ok && res?.result) {
        return res.result;
      }
      return {
        schema: "review/v1",
        decision: "reject",
        content: "",
        hunks: [],
        reason: "Review RPC failed",
      };
    } catch (e) {
      log("neph-client", `review error: ${e instanceof Error ? e.message : String(e)}`);
      return {
        schema: "review/v1",
        decision: "reject",
        content: "",
        hunks: [],
        reason: "Review failed or timed out",
      };
    }
  }

  async checktime(): Promise<void> {
    if (!this.client) return;
    await this.client.executeLua(RPC_CALL, ["buffers.check", {}]);
  }

  disconnect(): void {
    this.disconnected = true;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.client) {
      try {
        (this.client as unknown as { disconnect(): void }).disconnect();
      } catch {
        // ignore
      }
      this.client = null;
    }
    this.channelId = null;
    log("neph-client", "disconnected");
  }

  isConnected(): boolean {
    return this.client !== null && this.channelId !== null;
  }

  private _scheduleReconnect(): void {
    if (this.disconnected || this.reconnecting) return;
    this.reconnecting = true;

    const attempt = async () => {
      if (this.disconnected) {
        this.reconnecting = false;
        return;
      }
      try {
        log("neph-client", `reconnecting (delay=${this.reconnectDelay}ms)...`);
        await this.connect(this.socketPath!);
        if (this.agentName) {
          await this.register(this.agentName);
        }
        this.reconnectDelay = 100;
        this.reconnecting = false;
        log("neph-client", "reconnected successfully");
      } catch {
        this.reconnectDelay = Math.min(
          this.reconnectDelay * 2,
          NephClient.MAX_RECONNECT_DELAY,
        );
        if (!this.disconnected) {
          this.reconnectTimer = setTimeout(attempt, this.reconnectDelay);
        } else {
          this.reconnecting = false;
        }
      }
    };

    this.reconnectTimer = setTimeout(attempt, this.reconnectDelay);
  }
}
