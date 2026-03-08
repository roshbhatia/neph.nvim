## Context

`gate.ts` has 4 hardcoded parser functions (`parseClaude`, `parseCopilot`, `parseGemini`, `parseCursor`) that each read agent-specific field names from stdin JSON and normalize to `{ filePath, content }`. These parsers are tightly coupled to each agent's exact schema — different field names for the same concept (`file_path` vs `filepath`, `old_str` vs `old_string`), different nesting (`toolArgs` as a JSON string in Copilot), and different tool names (`Write`/`Edit` vs `write_file`/`edit_file`).

The existing contract test fixtures (`tests/fixtures/*.json`) pin expected schemas, and fuzz tests cover edge cases. But if an agent changes their format, the parser silently returns null and gate fails open (allows without review). No log, no warning.

## Goals / Non-Goals

**Goals:**
- Make agent schemas declarative so adding/updating an agent is a data change, not a logic change
- Log when a parser returns null on what looks like a file mutation, so silent degradation becomes visible
- Keep existing fail-open behavior and all external behavior identical

**Non-Goals:**
- Runtime schema auto-detection (too fragile, not worth the complexity)
- Changing exit codes, review flow, or gate lifecycle
- Supporting agents that don't use JSON on stdin

## Decisions

### 1. Declarative agent schema objects instead of parser functions

Each agent gets a schema definition object:

```typescript
interface AgentSchema {
  /** Tool names that represent write operations */
  writeTools: string[];
  /** Tool names that represent edit operations (old→new replacement) */
  editTools: string[];
  /** How to extract fields from the parsed stdin JSON */
  fields: {
    toolName: string;       // path to tool name field (e.g., "tool_name", "toolName")
    toolInput: string;      // path to tool input object (e.g., "tool_input", root)
    filePath: string;       // field name for file path within tool input
    content?: string;       // field name for content (writes)
    oldText?: string;       // field name for old text (edits)
    newText?: string;       // field name for new text (edits)
  };
  /** Optional: pre-processing step (e.g., Copilot's JSON-string toolArgs) */
  preprocess?: (input: Record<string, unknown>) => Record<string, unknown>;
  /** If true, this is a post-write notification only (no review, just checktime) */
  postWriteOnly?: boolean;
}
```

**Why over parser functions:** A schema object is inspectable, testable without execution, and makes the field mapping explicit. Adding a new agent is filling in a struct, not writing parsing logic.

**Alternative considered:** JSON schema files loaded at runtime. Rejected because the `preprocess` hook (needed for Copilot's JSON-string toolArgs) requires code, and co-locating schema + code in one TS file is simpler.

### 2. Single generic `parseWithSchema()` function replaces all 4 parsers

One function takes an `AgentSchema` and stdin JSON, returns `GatePayload | null`. The existing `reconstructEdit()` helper stays — it's schema-agnostic already.

**Why:** Eliminates duplicated field-access patterns across 4 functions. The generic parser is ~30 lines instead of 4 × ~25 lines.

### 3. Debug logging on null-return with file-path heuristic

When `parseWithSchema()` returns null (no match), scan the input for fields that look like file paths (contain `/` or `\`, or match common field names like `file_path`, `filepath`, `filePath`, `path`). If found, log a warning to `/tmp/neph-debug.log`:

```
[HH:MM:SS.mmm] [ts] [gate] parser returned null for agent "claude" but input contains path-like field "file_path" — schema may need updating
```

**Why:** This turns silent degradation into visible degradation. The log is only written when `NEPH_DEBUG=1` (existing debug infrastructure), so zero overhead in production.

### 4. Keep `PARSERS` dict as the public API, backed by schemas

```typescript
const SCHEMAS: Record<string, AgentSchema> = { claude: ..., copilot: ..., gemini: ..., cursor: ... };

// Generic parser using schema
function parseWithSchema(schema: AgentSchema, input: unknown): GatePayload | null { ... }

// Public API stays the same shape
export const PARSERS: Record<string, (input: unknown) => GatePayload | null> = Object.fromEntries(
  Object.entries(SCHEMAS).map(([name, schema]) => [name, (input: unknown) => parseWithSchema(schema, input)])
);
```

**Why:** Existing tests import `parseClaude`, `parseCopilot`, etc. We keep named exports that delegate to the generic parser. Zero test changes for contract tests and fuzz tests — they call the same functions with the same inputs and expect the same outputs.

## Risks / Trade-offs

- **[Risk] Schema object may not cover a future agent's quirks** → Mitigation: the `preprocess` hook is an escape hatch for non-standard formats. Worst case, a new agent can still use a custom parser function alongside schemas.
- **[Risk] Debug logging adds a dependency on log.ts in neph-cli** → Mitigation: `log.ts` already exists at `tools/lib/log.ts` and is used by pi. Import it.
- **[Trade-off] Named parser exports become wrappers** → Acceptable: the public API surface doesn't change, just the implementation behind it.
