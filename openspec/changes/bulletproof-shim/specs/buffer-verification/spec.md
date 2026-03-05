# Buffer Verification

Post-review verification that a Neovim buffer's content matches the expected final state.

## Capability

**buffer-verification** — Verify Neovim buffer content via pynvim.Buffer API after a review operation completes.

## Rationale

After a user reviews proposed content and the shim applies the accepted hunks to disk, the buffer in Neovim may not immediately reflect the new file state (e.g., if `autoread` is off or the user hasn't switched focus). Buffer verification detects this mismatch and surfaces it to the agent via `verification_error` in the ReviewEnvelope, allowing the agent to prompt the user or retry the operation.

## ADDED Requirements

### Requirement: verify_buffer function

- Function `verify_buffer(nvim: pynvim.Nvim, file_path: str, expected: str) -> dict`
  - Searches `nvim.buffers` for a buffer whose `.name` matches `os.path.abspath(file_path)`
  - If found: reads `buf[:]`, joins with `\n`, compares to `expected`
  - On match: returns `{}`
  - On mismatch: computes unified diff and returns `{"verification_error": diff_str}`
  - If buffer not found or exception on read: returns `{"verification_skipped": True}`
- Call site in `cmd_review`: after reading the ReviewEnvelope from `result_path`, extract `final_content = envelope.get("content", "")`, call `verify_buffer(nvim, file_path, final_content)`, merge result keys into envelope

### `tools/core/tests/test_shim.py`

- Class `TestVerifyBuffer` with tests:
  - `test_match_returns_empty_dict` — mock buffer with matching content → `{}`
  - `test_mismatch_returns_verification_error` — mock buffer with different content → `{"verification_error": ...}`
  - `test_not_found_returns_verification_skipped` — empty `nvim.buffers` → `{"verification_skipped": True}`
  - `test_exception_on_read_returns_skipped` — `buf.__getitem__` raises exception → `{"verification_skipped": True}`

## Delta Headers

**buffer-verification**: ADDED (new capability — verify buffer state post-review)
