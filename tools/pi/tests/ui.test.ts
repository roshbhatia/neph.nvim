import { describe, it, expect, vi, beforeEach } from "vitest";

const mockNephInstance = {
  connect: vi.fn().mockResolvedValue(undefined),
  register: vi.fn().mockResolvedValue(undefined),
  onPrompt: vi.fn(),
  uiSelect: vi.fn(),
  uiInput: vi.fn(),
  uiNotify: vi.fn(),
  isConnected: vi.fn().mockReturnValue(true),
};

vi.mock("../../lib/neph-client", () => ({
  NephClient: vi.fn(() => mockNephInstance),
}));
vi.mock("../../lib/log", () => ({ debug: vi.fn() }));
vi.mock("@mariozechner/pi-coding-agent", () => ({
  createWriteTool: vi.fn(() => ({ parameters: {} })),
  createEditTool: vi.fn(() => ({ parameters: {} })),
}));

import piExtension from "../pi.ts";

function makePI() {
  const handlers: Record<string, Function[]> = {};
  return {
    on(event: string, handler: Function) {
      (handlers[event] ??= []).push(handler);
    },
    registerTool: vi.fn(),
    sendUserMessage: vi.fn(),
    async emit(event: string, ...args: any[]) {
      const fns = handlers[event] ?? [];
      return Promise.all(fns.map((fn) => fn(...args)));
    },
    ui: {
      setStatus: vi.fn(),
      select: vi.fn().mockResolvedValue("original"),
      input: vi.fn().mockResolvedValue("original"),
      confirm: vi.fn().mockResolvedValue(true),
      notify: vi.fn(),
    },
  };
}

describe("pi extension UI wrapping", () => {
  let pi: any;

  beforeEach(() => {
    vi.clearAllMocks();
    mockNephInstance.isConnected.mockReturnValue(true);
    pi = makePI();
    piExtension(pi);
  });

  it("wraps ctx.ui.select to use NephClient", async () => {
    mockNephInstance.uiSelect.mockResolvedValue("neph choice");
    const ctx = { ui: pi.ui };
    await pi.emit("session_start", {}, ctx);

    const result = await ctx.ui.select("Title", ["A", "B"]);
    expect(mockNephInstance.uiSelect).toHaveBeenCalledWith("Title", ["A", "B"]);
    expect(result).toBe("neph choice");
  });

  it("falls back to original ui.select if not connected", async () => {
    mockNephInstance.isConnected.mockReturnValue(false);
    const ctx = { ui: pi.ui };
    await pi.emit("session_start", {}, ctx);

    const result = await ctx.ui.select("Title", ["A", "B"]);
    expect(mockNephInstance.uiSelect).not.toHaveBeenCalled();
    expect(result).toBe("original");
  });

  it("wraps ctx.ui.input to use NephClient", async () => {
    mockNephInstance.uiInput.mockResolvedValue("neph input");
    const ctx = { ui: pi.ui };
    await pi.emit("session_start", {}, ctx);

    const result = await ctx.ui.input("Prompt", "default");
    expect(mockNephInstance.uiInput).toHaveBeenCalledWith("Prompt", "default");
    expect(result).toBe("neph input");
  });

  it("wraps ctx.ui.confirm to use NephClient uiSelect", async () => {
    mockNephInstance.uiSelect.mockResolvedValue("Yes");
    const ctx = { ui: pi.ui };
    await pi.emit("session_start", {}, ctx);

    const result = await ctx.ui.confirm("Title", "Are you sure?");
    expect(mockNephInstance.uiSelect).toHaveBeenCalledWith(
      "Title\nAre you sure?",
      ["Yes", "No"],
    );
    expect(result).toBe(true);
  });

  it("wraps ctx.ui.notify to use NephClient uiNotify", async () => {
    const ctx = { ui: pi.ui };
    await pi.emit("session_start", {}, ctx);

    ctx.ui.notify("Something happened", "warn");
    expect(mockNephInstance.uiNotify).toHaveBeenCalledWith(
      "Something happened",
      "warn",
    );
  });
});
