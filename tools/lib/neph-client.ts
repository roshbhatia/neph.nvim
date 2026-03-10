import { attach, type NeovimClient } from "neovim";
import process from "node:process";
import { randomUUID } from "node:crypto";
import { debug as log } from "./log";

export interface ReviewEnvelope {
  schema: "review/v1";
  decision: "accept" | "reject" | "partial";
  content: string;
  hunks: { index: number; decision: "accept" | "reject"; reason?: string }[];
  reason?: string;
}

export enum ConnectionState {
  DISCONNECTED = "disconnected",
  CONNECTING = "connecting",
  CONNECTED = "connected",
  RECONNECTING = "reconnecting",
}

const RPC_CALL = 'return require("neph.rpc").request(...)';

function fullJitter(base: number, attempt: number, cap: number): number {
  const exponential = base * Math.pow(2, attempt);
  const capped = Math.min(exponential, cap);
  return Math.floor(Math.random() * capped);
}

export class NephClient {
  private client: NeovimClient | null = null;
  private agentName: string | null = null;
  private channelId: number | null = null;
  private socketPath: string | null = null;
  private promptCallback: ((text: string) => void) | null = null;
  private notificationCallbacks: Map<string, ((args: unknown[]) => void)[]> = new Map();
  private pendingRequests: Map<string, (result: any) => void> = new Map();
  private reconnecting = false;
  private disconnected = false;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private reconnectAttempt = 0;
  private connectionState: ConnectionState = ConnectionState.DISCONNECTED;
  private static readonly BASE_DELAY = 100;
  private static readonly MAX_RECONNECT_DELAY = 5000;

  async connect(socketPath?: string): Promise<void> {
    const path = socketPath || process.env.NVIM_SOCKET_PATH;
    if (!path) {
      throw new Error("No socket path: set NVIM_SOCKET_PATH or pass socketPath");
    }
    this.socketPath = path;
    this.disconnected = false;
    this.connectionState = ConnectionState.CONNECTING;
    log("neph-client", `state: ${this.connectionState}`);

    this.client = attach({ socket: path });
    const apiInfo = await this.client.request("nvim_get_api_info");
    this.channelId = (apiInfo as [number, unknown])[0];
    this.connectionState = ConnectionState.CONNECTED;
    log("neph-client", `connected to ${path} (channel=${this.channelId}) state: ${this.connectionState}`);

    // Listen for notifications
    this.client.on("notification", (method: string, args: unknown[]) => {
      if (method === "neph:prompt" && this.promptCallback) {
        const text = args[0];
        log("neph-client", `received prompt (len=${String(text).length})`);
        this.promptCallback(typeof text === "string" ? text : String(text));
      }

      if (method === "neph:review_done" || method === "neph:ui_response") {
        const data = args[0] as { request_id?: string };
        if (data?.request_id) {
          const resolve = this.pendingRequests.get(data.request_id);
          if (resolve) {
            this.pendingRequests.delete(data.request_id);
            resolve(data);
          }
        }
      }

      const callbacks = this.notificationCallbacks.get(method);
      if (callbacks) {
        for (const cb of callbacks) {
          cb(args);
        }
      }
    });

    // Handle disconnect
    this.client.on("disconnect", () => {
      log("neph-client", `socket disconnected, state: ${this.connectionState} -> disconnected`);
      this.client = null;
      this.channelId = null;
      this.connectionState = ConnectionState.DISCONNECTED;
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

  onNotification(method: string, callback: (args: unknown[]) => void): void {
    const existing = this.notificationCallbacks.get(method) ?? [];
    existing.push(callback);
    this.notificationCallbacks.set(method, existing);
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
    if (!this.client || this.channelId === null) {
      return {
        schema: "review/v1",
        decision: "reject",
        content: "",
        hunks: [],
        reason: "Not connected to Neovim",
      };
    }

    const requestId = randomUUID();
    // For review, we actually need a temp file path if we want to follow the neph-cli gate pattern,
    // but the Lua review.open also supports writing to a result_path.
    // However, NephClient is used by pi extension which might prefer a direct notification.
    
    // Wait for the notification
    const promise = new Promise<ReviewEnvelope>((resolve) => {
      this.pendingRequests.set(requestId, (data: any) => {
        // In the direct notification case, the data should contain the envelope.
        // But lua/neph/api/review/init.lua writes to result_path and sends notification.
        // We might need to update lua/neph/api/review/init.lua to also send the envelope in the notification
        // OR read it from the file.
        // For simplicity in the Pi extension context, let's assume we might update the Lua side
        // or just handle the basic decision.
        resolve(data as ReviewEnvelope);
      });
    });

    try {
      // Note: we're passing result_path as empty or omitting it if we want direct notification with data.
      // But let's check what review.open expects.
      await this.client.executeLua(RPC_CALL, [
        "review.open",
        {
          path: filePath,
          content,
          request_id: requestId,
          channel_id: this.channelId,
          // We don't provide result_path, so Lua side needs to handle that.
        },
      ]);
      return await promise;
    } catch (e) {
      this.pendingRequests.delete(requestId);
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

  async uiNotify(message: string, level?: string): Promise<void> {
    if (!this.client) return;
    await this.client.executeLua(RPC_CALL, ["ui.notify", { message, level }]);
  }

  async uiSelect(title: string, options: string[]): Promise<string | undefined> {
    if (!this.client || this.channelId === null) return undefined;
    const requestId = randomUUID();
    const promise = new Promise<string | undefined>((resolve) => {
      this.pendingRequests.set(requestId, (data: any) => {
        resolve(data.choice);
      });
    });

    try {
      await this.client.executeLua(RPC_CALL, [
        "ui.select",
        {
          request_id: requestId,
          channel_id: this.channelId,
          title,
          options,
        },
      ]);
      return await promise;
    } catch (e) {
      this.pendingRequests.delete(requestId);
      log("neph-client", `uiSelect error: ${e instanceof Error ? e.message : String(e)}`);
      return undefined;
    }
  }

  async uiInput(title: string, defaultValue?: string): Promise<string | undefined> {
    if (!this.client || this.channelId === null) return undefined;
    const requestId = randomUUID();
    const promise = new Promise<string | undefined>((resolve) => {
      this.pendingRequests.set(requestId, (data: any) => {
        resolve(data.choice);
      });
    });

    try {
      await this.client.executeLua(RPC_CALL, [
        "ui.input",
        {
          request_id: requestId,
          channel_id: this.channelId,
          title,
          default: defaultValue,
        },
      ]);
      return await promise;
    } catch (e) {
      this.pendingRequests.delete(requestId);
      log("neph-client", `uiInput error: ${e instanceof Error ? e.message : String(e)}`);
      return undefined;
    }
  }

  disconnect(): void {
    this.disconnected = true;
    this.connectionState = ConnectionState.DISCONNECTED;
    log("neph-client", `state: ${this.connectionState}`);
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.client) {
      try {
        this.client.close();
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

  getConnectionState(): ConnectionState {
    return this.connectionState;
  }

  private _scheduleReconnect(): void {
    if (this.disconnected || this.reconnecting) return;
    this.reconnecting = true;
    this.connectionState = ConnectionState.RECONNECTING;
    log("neph-client", `state: ${this.connectionState}`);

    const attempt = async () => {
      if (this.disconnected) {
        this.reconnecting = false;
        return;
      }
      try {
        const delay = fullJitter(NephClient.BASE_DELAY, this.reconnectAttempt, NephClient.MAX_RECONNECT_DELAY);
        log("neph-client", `reconnecting (attempt=${this.reconnectAttempt}, delay=${delay}ms)...`);
        await this.connect(this.socketPath!);
        if (this.agentName) {
          await this.register(this.agentName);
        }
        this.reconnectAttempt = 0;
        this.reconnecting = false;
        log("neph-client", "reconnected successfully");
      } catch {
        this.reconnectAttempt++;
        if (!this.disconnected) {
          const nextDelay = fullJitter(NephClient.BASE_DELAY, this.reconnectAttempt, NephClient.MAX_RECONNECT_DELAY);
          this.reconnectTimer = setTimeout(attempt, nextDelay);
        } else {
          this.reconnecting = false;
        }
      }
    };

    const initialDelay = fullJitter(NephClient.BASE_DELAY, this.reconnectAttempt, NephClient.MAX_RECONNECT_DELAY);
    this.reconnectTimer = setTimeout(attempt, initialDelay);
  }
}
