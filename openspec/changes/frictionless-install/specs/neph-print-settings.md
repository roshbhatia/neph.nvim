# Spec: neph print-settings

## Command

```
neph print-settings <agent>
```

## Behavior

1. Resolves `<agent>` to an integration from the `INTEGRATIONS` list.
2. Reads `integration.templatePath` from disk.
3. Writes the file contents as a minified JSON string to stdout (no trailing
   newline from the JSON itself; one `\n` at the very end).
4. Exits 0.

## Error Cases

| Condition                        | stderr message                               | Exit |
|----------------------------------|----------------------------------------------|------|
| Missing agent argument           | `Usage: neph print-settings <agent>`         | 1    |
| Unknown agent name               | `Unknown integration: <name>`                | 1    |
| Agent has no template (cupcake)  | `<name>: no template (cupcake integration)`  | 1    |
| Template file missing on disk    | `Cannot read <path>: <err>`                  | 1    |
| Template is not valid JSON       | `Invalid JSON at <path>: <err>`              | 1    |

## Output Format

Minified JSON (no whitespace beyond what's in string values). Example for
`neph print-settings claude`:

```
{"hooks":{"PreToolUse":[{"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":"PATH=$HOME/.local/bin:$PATH neph integration hook claude"}]}],...}}
```

The output is designed to be consumed directly by `claude --settings`:

```bash
claude --settings "$(neph print-settings claude)"
```

## Notes

- The command string in the template (`PATH=$HOME/.local/bin:$PATH neph ...`)
  is output as-is. The alias calling `neph print-settings` is already running
  in the user's shell where neph is resolvable.
- `print-settings` does NOT substitute the absolute binary path. That's
  `install`'s job.
- Transport is not required (no `$NVIM` needed).
