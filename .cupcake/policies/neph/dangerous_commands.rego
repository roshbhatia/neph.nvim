# METADATA
# scope: package
# custom:
#   routing:
#     required_events: ["PreToolUse", "BeforeTool"]
#     required_tools: ["Bash", "run_shell_command"]

# Policy: dangerous_commands
# Intercepts Bash/shell tool invocations and blocks commands that could cause
# irreversible damage to the repository or bypass safety mechanisms.
# Evaluated on PreToolUse and BeforeTool events for Bash and run_shell_command tools.
package cupcake.policies.neph.dangerous_commands

import rego.v1

# Rule: Block recursive force-delete commands (rm -rf).
# Prevents accidental or malicious deletion of directory trees.
deny contains decision if {
	bash_tool
	command := get_command
	contains(command, "rm -rf")
	decision := {
		"rule_id": "NEPH-DANGER-RM-RF",
		"reason": "Blocked: rm -rf is too dangerous",
		"severity": "HIGH",
	}
}

# Rule: Block git force-push (git push -f / --force).
# Force-pushing rewrites remote history and can destroy collaborators' work.
deny contains decision if {
	bash_tool
	command := get_command
	regex.match(`git\s+push\s+.*(-f|--force)`, command)
	decision := {
		"rule_id": "NEPH-DANGER-FORCE-PUSH",
		"reason": "Blocked: force push is not allowed",
		"severity": "HIGH",
	}
}

# Rule: Block --no-verify flag on any command (e.g., git commit --no-verify).
# The --no-verify flag skips pre-commit/pre-push hooks, bypassing lint and test gates.
deny contains decision if {
	bash_tool
	command := get_command
	contains(command, "--no-verify")
	decision := {
		"rule_id": "NEPH-DANGER-NO-VERIFY",
		"reason": "Blocked: --no-verify bypasses safety hooks",
		"severity": "MEDIUM",
	}
}

# Helper: Returns true when the current tool invocation is a shell/bash tool.
bash_tool if {
	input.tool_name in ["Bash", "run_shell_command"]
}

# Helper: Extracts the command string from the tool input.
# Falls back to an empty string if the field is missing.
get_command := cmd if {
	cmd := input.tool_input.command
} else := "" if true
