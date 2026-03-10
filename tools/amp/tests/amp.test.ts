import { describe, it, expect, vi, beforeEach } from "vitest";

const mockNephInstance = {
  connect: vi.fn().mockResolvedValue(undefined),
  register: vi.fn().mockResolvedValue(undefined),
  onPrompt: vi.fn(),
  setStatus: vi.fn().mockResolvedValue(undefined),
  unsetStatus: vi.fn().mockResolvedValue(undefined),
  review: vi.fn().mockResolvedValue({
    schema: "review/v1",
    decision: "accept",
    content: "accepted",
    hunks: [],
  }),
  checktime: vi.fn().mockResolvedValue(undefined),
  uiSelect: vi.fn(),
  uiInput: vi.fn(),
  uiNotify: vi.fn(),
};

vi.mock("../../lib/neph-client", () => ({
  NephClient: vi.fn(function () {
    return mockNephInstance;
  }),
}));
vi.mock("../../lib/log", () => ({ debug: vi.fn() }));
vi.mock("node:fs", () => ({ readFileSync: vi.fn() }));

import ampPlugin from "../neph-plugin.ts";

function makeAmp() {
  const handlers: Record<string, Function[]> = {};
  return {
    on(event: string, handler: Function) {
      (handlers[event] ??= []).push(handler);
    },
    async emit(event: string, ...args: any[]) {
      const fns = handlers[event] ?? [];
      return Promise.all(fns.map((fn) => fn(...args)));
    },
    ui: {
      notify: vi.fn(),
      confirm: vi.fn().mockResolvedValue(true),
      input: vi.fn().mockResolvedValue("original"),
    },
    thread: {
      append: vi.fn(),
    },
  };
}

describe("amp companion bridge", () => {
  let amp: any;

  beforeEach(() => {
    vi.clearAllMocks();
    amp = makeAmp();
    ampPlugin(amp);
  });

  it("registers as amp agent on session.start", async () => {
    await amp.emit("session.start");
    expect(mockNephInstance.connect).toHaveBeenCalled();
    expect(mockNephInstance.register).toHaveBeenCalledWith("amp");
    expect(mockNephInstance.setStatus).toHaveBeenCalledWith(
      "amp_active",
      "true",
    );
  });

  it("bridges agent start/end status", async () => {
    await amp.emit("agent.start");
    expect(mockNephInstance.setStatus).toHaveBeenCalledWith(
      "amp_running",
      "true",
    );

    await amp.emit("agent.end");
    expect(mockNephInstance.unsetStatus).toHaveBeenCalledWith("amp_running");
    expect(mockNephInstance.checktime).toHaveBeenCalled();
  });

  it("intercepts tool.call for review", async () => {
    mockNephInstance.review.mockResolvedValue({
      schema: "review/v1",
      decision: "accept",
      content: "ok",
      hunks: [],
    });

    const result = await amp.emit("tool.call", {
      tool: "create_file",
      input: { file_path: "test.ts", content: "hello" },
    });

    expect(mockNephInstance.review).toHaveBeenCalledWith("test.ts", "hello");
    expect(result[0]).toEqual({ action: "allow" });
  });

  it("wraps ctx.ui methods on session.start", async () => {
    await amp.emit("session.start");

    // Test notify
    amp.ui.notify("hello", "info");
    expect(mockNephInstance.uiNotify).toHaveBeenCalledWith("hello", "info");
    expect(amp.ui.notify).toBeDefined(); // Wrapper should exist

    // Test confirm
    mockNephInstance.uiSelect.mockResolvedValue("Yes");
    const confirmed = await amp.ui.confirm("Title", "Message");
    expect(mockNephInstance.uiSelect).toHaveBeenCalledWith("Title\nMessage", [
      "Yes",
      "No",
    ]);
    expect(confirmed).toBe(true);

    // Test input
    mockNephInstance.uiInput.mockResolvedValue("neph input");
    const input = await amp.ui.input("Prompt", "placeholder");
    expect(mockNephInstance.uiInput).toHaveBeenCalledWith(
      "Prompt",
      "placeholder",
    );
    expect(input).toBe("neph input");
  });

  it("forwards Neovim prompts to Amp thread", async () => {
    await amp.emit("session.start");

    const promptCallback = mockNephInstance.onPrompt.mock.calls[0][0];
    promptCallback("fix this");

    expect(amp.thread.append).toHaveBeenCalledWith({
      role: "user",
      content: "fix this",
    });
  });
});
