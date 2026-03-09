import { describe, it, expect, vi, beforeEach } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { createDiffTools, type DiffNotificationSink } from "../src/diff_bridge";

// Mock NephClient
function createMockNeph(reviewResult: {
  decision: "accept" | "reject" | "partial";
  content: string;
}) {
  return {
    review: vi.fn().mockResolvedValue({
      schema: "review/v1",
      decision: reviewResult.decision,
      content: reviewResult.content,
      hunks: [],
    }),
    checktime: vi.fn().mockResolvedValue(undefined),
  } as any;
}

function createMockSink(): DiffNotificationSink & {
  accepted: { filePath: string; content: string }[];
  rejected: string[];
} {
  const sink = {
    accepted: [] as { filePath: string; content: string }[],
    rejected: [] as string[],
    sendDiffAccepted(filePath: string, content: string): void {
      sink.accepted.push({ filePath, content });
    },
    sendDiffRejected(filePath: string): void {
      sink.rejected.push(filePath);
    },
  };
  return sink;
}

describe("openDiff", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "neph-diff-test-"));
  });

  it("calls neph.review and writes accepted content to disk", async () => {
    const filePath = path.join(tmpDir, "test.txt");
    fs.writeFileSync(filePath, "old content");

    const neph = createMockNeph({ decision: "accept", content: "new content" });
    const sink = createMockSink();
    const tools = createDiffTools(neph, sink);

    const result = await tools.openDiff.handler({ filePath, newContent: "new content" });

    expect(neph.review).toHaveBeenCalledWith(filePath, "new content");
    expect(result.content).toEqual([]);
    expect(fs.readFileSync(filePath, "utf-8")).toBe("new content");
    expect(sink.accepted).toHaveLength(1);
    expect(sink.accepted[0].content).toBe("new content");
  });

  it("sends diffRejected on reject", async () => {
    const filePath = path.join(tmpDir, "test.txt");
    fs.writeFileSync(filePath, "old content");

    const neph = createMockNeph({ decision: "reject", content: "" });
    const sink = createMockSink();
    const tools = createDiffTools(neph, sink);

    await tools.openDiff.handler({ filePath, newContent: "new content" });

    expect(sink.rejected).toHaveLength(1);
    expect(sink.rejected[0]).toBe(filePath);
    expect(fs.readFileSync(filePath, "utf-8")).toBe("old content");
  });

  it("writes partial content on partial accept", async () => {
    const filePath = path.join(tmpDir, "test.txt");
    fs.writeFileSync(filePath, "old content");

    const neph = createMockNeph({ decision: "partial", content: "partial content" });
    const sink = createMockSink();
    const tools = createDiffTools(neph, sink);

    await tools.openDiff.handler({ filePath, newContent: "full new content" });

    expect(fs.readFileSync(filePath, "utf-8")).toBe("partial content");
    expect(sink.accepted).toHaveLength(1);
    expect(sink.accepted[0].content).toBe("partial content");
  });

  it("returns error for missing filePath", async () => {
    const neph = createMockNeph({ decision: "accept", content: "" });
    const sink = createMockSink();
    const tools = createDiffTools(neph, sink);

    const result = await tools.openDiff.handler({ newContent: "content" });

    expect(result.isError).toBe(true);
  });

  it("creates parent directories for new files", async () => {
    const filePath = path.join(tmpDir, "sub", "dir", "new.txt");

    const neph = createMockNeph({ decision: "accept", content: "new file" });
    const sink = createMockSink();
    const tools = createDiffTools(neph, sink);

    await tools.openDiff.handler({ filePath, newContent: "new file" });

    expect(fs.readFileSync(filePath, "utf-8")).toBe("new file");
  });
});

describe("closeDiff", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "neph-diff-test-"));
  });

  it("returns current file content", async () => {
    const filePath = path.join(tmpDir, "test.txt");
    fs.writeFileSync(filePath, "current content");

    const neph = createMockNeph({ decision: "accept", content: "" });
    const sink = createMockSink();
    const tools = createDiffTools(neph, sink);

    const result = await tools.closeDiff.handler({ filePath });

    expect(result.content).toEqual([{ type: "text", text: "current content" }]);
  });

  it("returns empty for nonexistent file", async () => {
    const filePath = path.join(tmpDir, "nonexistent.txt");

    const neph = createMockNeph({ decision: "accept", content: "" });
    const sink = createMockSink();
    const tools = createDiffTools(neph, sink);

    const result = await tools.closeDiff.handler({ filePath });

    expect(result.content).toEqual([{ type: "text", text: "" }]);
  });
});
