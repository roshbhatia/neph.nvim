import { describe, it, expect, vi, beforeEach } from "vitest";

const mockNephInstance = {
  connect: vi.fn().mockResolvedValue(undefined),
  register: vi.fn().mockResolvedValue(undefined),
  onPrompt: vi.fn(),
  setStatus: vi.fn().mockResolvedValue(undefined),
  unsetStatus: vi.fn().mockResolvedValue(undefined),
  checktime: vi.fn().mockResolvedValue(undefined),
  uiSelect: vi.fn(),
};

vi.mock("../../lib/neph-client", () => ({
  NephClient: vi.fn(function() { return mockNephInstance; }),
}));
vi.mock("../../lib/log", () => ({ debug: vi.fn() }));

// Import after mocks
import { NephCompanion } from "../opencode.ts";

function makeOpenCode() {
  const chatAppend = vi.fn();
  return {
    client: {
      chat: {
        append: chatAppend,
      },
    },
  };
}

describe("opencode companion bridge", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockNephInstance.connect.mockResolvedValue(undefined);
    mockNephInstance.register.mockResolvedValue(undefined);
    mockNephInstance.setStatus.mockResolvedValue(undefined);
    mockNephInstance.unsetStatus.mockResolvedValue(undefined);
    mockNephInstance.checktime.mockResolvedValue(undefined);
  });

  it("registers as opencode agent on initialization", async () => {
    const oc = makeOpenCode();
    await NephCompanion(oc as any);
    expect(mockNephInstance.connect).toHaveBeenCalled();
    expect(mockNephInstance.register).toHaveBeenCalledWith("opencode");
  });

  it("bridges session lifecycle events", async () => {
    const oc = makeOpenCode();
    const plugin: any = await NephCompanion(oc as any);

    await plugin.event({ event: { type: "session.created" } });
    expect(mockNephInstance.setStatus).toHaveBeenCalledWith("opencode_active", "true");

    await plugin.event({ event: { type: "session.busy" } });
    expect(mockNephInstance.setStatus).toHaveBeenCalledWith("opencode_running", "true");

    await plugin.event({ event: { type: "session.idle" } });
    expect(mockNephInstance.unsetStatus).toHaveBeenCalledWith("opencode_running");
    expect(mockNephInstance.checktime).toHaveBeenCalled();
  });

  it("intercepts shell tool for approval", async () => {
    const oc = makeOpenCode();
    const plugin: any = await NephCompanion(oc as any);

    mockNephInstance.uiSelect.mockResolvedValue("Yes");
    await plugin.tool.execute.before({ tool: "shell", args: { command: "rm -rf /" } });
    expect(mockNephInstance.uiSelect).toHaveBeenCalledWith(
      expect.stringContaining("rm -rf /"),
      ["Yes", "No"]
    );

    mockNephInstance.uiSelect.mockResolvedValue("No");
    await expect(
      plugin.tool.execute.before({ tool: "shell", args: { command: "ls" } })
    ).rejects.toThrow(/User denied/);
  });

  it("forwards Neovim prompts to OpenCode chat", async () => {
    const oc = makeOpenCode();
    await NephCompanion(oc as any);

    // Get the callback passed to onPrompt
    const promptCallback = mockNephInstance.onPrompt.mock.calls[0][0];
    promptCallback("hello from nvim");

    expect(oc.client.chat.append).toHaveBeenCalledWith({
      role: "user",
      content: "hello from nvim",
    });
  });
});
