import { describe, it, expect, vi, beforeEach } from "vitest";

// Mock the neovim module before importing NephClient
vi.mock("neovim", () => {
  const mockClient = {
    request: vi.fn(),
    executeLua: vi.fn(),
    on: vi.fn(),
    disconnect: vi.fn(),
  };
  return {
    attach: vi.fn(() => mockClient),
    __mockClient: mockClient,
  };
});

// Must import after mock
import { NephClient } from "../neph-client";
import { attach } from "neovim";

function getMockClient() {
  return (attach as ReturnType<typeof vi.fn>).mock.results[0]?.value;
}

describe("NephClient", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    process.env.NVIM_SOCKET_PATH = "/tmp/test-nvim.sock";
  });

  it("connect attaches to socket and gets channel ID", async () => {
    const client = new NephClient();
    const mock = (await import("neovim") as any).__mockClient;
    mock.request.mockResolvedValue([42, {}]);
    mock.on.mockImplementation(() => {});

    await client.connect("/tmp/test.sock");

    expect(attach).toHaveBeenCalledWith({ socket: "/tmp/test.sock" });
    expect(mock.request).toHaveBeenCalledWith("nvim_get_api_info");
    expect(client.isConnected()).toBe(true);

    client.disconnect();
  });

  it("connect throws when no socket path available", async () => {
    delete process.env.NVIM_SOCKET_PATH;
    const client = new NephClient();
    await expect(client.connect()).rejects.toThrow("No socket path");
  });

  it("register sends bus.register RPC with channel ID", async () => {
    const client = new NephClient();
    const mock = (await import("neovim") as any).__mockClient;
    mock.request.mockResolvedValue([7, {}]);
    mock.on.mockImplementation(() => {});
    mock.executeLua.mockResolvedValue({ ok: true, result: { ok: true } });

    await client.connect("/tmp/test.sock");
    await client.register("pi");

    expect(mock.executeLua).toHaveBeenCalledWith(
      'return require("neph.rpc").request(...)',
      ["bus.register", { name: "pi", channel: 7 }],
    );

    client.disconnect();
  });

  it("onPrompt callback fires on neph:prompt notification", async () => {
    const client = new NephClient();
    const mock = (await import("neovim") as any).__mockClient;
    mock.request.mockResolvedValue([1, {}]);

    // Capture the notification handler
    let notifHandler: ((method: string, args: unknown[]) => void) | null = null;
    mock.on.mockImplementation((event: string, handler: (...args: unknown[]) => void) => {
      if (event === "notification") {
        notifHandler = handler as (method: string, args: unknown[]) => void;
      }
    });

    await client.connect("/tmp/test.sock");

    const callback = vi.fn();
    client.onPrompt(callback);

    // Simulate notification
    expect(notifHandler).not.toBeNull();
    notifHandler!("neph:prompt", ["hello world"]);

    expect(callback).toHaveBeenCalledWith("hello world");

    client.disconnect();
  });

  it("disconnect sets state to not connected", async () => {
    const client = new NephClient();
    const mock = (await import("neovim") as any).__mockClient;
    mock.request.mockResolvedValue([1, {}]);
    mock.on.mockImplementation(() => {});

    await client.connect("/tmp/test.sock");
    expect(client.isConnected()).toBe(true);

    client.disconnect();
    expect(client.isConnected()).toBe(false);
  });

  it("setStatus calls status.set RPC", async () => {
    const client = new NephClient();
    const mock = (await import("neovim") as any).__mockClient;
    mock.request.mockResolvedValue([1, {}]);
    mock.on.mockImplementation(() => {});
    mock.executeLua.mockResolvedValue({ ok: true });

    await client.connect("/tmp/test.sock");
    await client.setStatus("pi_running", "true");

    expect(mock.executeLua).toHaveBeenCalledWith(
      'return require("neph.rpc").request(...)',
      ["status.set", { name: "pi_running", value: "true" }],
    );

    client.disconnect();
  });
});
