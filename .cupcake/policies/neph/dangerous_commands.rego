# METADATA
# scope: package
# custom:
#   routing:
#     required_events: ["PreToolUse", "BeforeTool"]
#     required_tools: ["Bash", "run_shell_command"]
package cupcake.policies.neph.dangerous_commands

import rego.v1

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

bash_tool if {
	input.tool_name in ["Bash", "run_shell_command"]
}

get_command := cmd if {
	cmd := input.tool_input.command
} else := "" if true
