# METADATA
# scope: package
# custom:
#   routing:
#     required_events: ["PreToolUse", "BeforeTool"]
#     required_tools: ["Write", "Edit", "write_file", "edit_file", "replace"]
package cupcake.policies.neph.protected_paths

import rego.v1

# Protected path patterns — extend this list per project
protected_patterns := [
	".env",
	".env.local",
	".env.production",
	"credentials.json",
	"secrets.yaml",
	"id_rsa",
	"id_ed25519",
]

deny contains decision if {
	file_path := get_file_path
	file_path != ""
	some pattern in protected_patterns
	endswith(file_path, pattern)
	decision := {
		"rule_id": "NEPH-PROTECTED-PATH",
		"reason": sprintf("Blocked: write to protected path %s", [file_path]),
		"severity": "HIGH",
	}
}

get_file_path := fp if {
	fp := input.tool_input.file_path
} else := fp if {
	fp := input.tool_input.filepath
} else := "" if true
