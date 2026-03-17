package cupcake.policies.neph.dangerous_commands_test

import rego.v1

import data.cupcake.policies.neph.dangerous_commands

test_block_rm_rf if {
	result := dangerous_commands.deny with input as {
		"tool_name": "Bash",
		"tool_input": {"command": "rm -rf /"},
	}
	count(result) > 0
}

test_block_force_push if {
	result := dangerous_commands.deny with input as {
		"tool_name": "Bash",
		"tool_input": {"command": "git push --force origin main"},
	}
	count(result) > 0
}

test_block_force_push_short_flag if {
	result := dangerous_commands.deny with input as {
		"tool_name": "Bash",
		"tool_input": {"command": "git push -f origin main"},
	}
	count(result) > 0
}

test_block_no_verify if {
	result := dangerous_commands.deny with input as {
		"tool_name": "Bash",
		"tool_input": {"command": "git commit --no-verify -m 'skip hooks'"},
	}
	count(result) > 0
}

test_allow_safe_command if {
	result := dangerous_commands.deny with input as {
		"tool_name": "Bash",
		"tool_input": {"command": "npm test"},
	}
	count(result) == 0
}

test_allow_non_bash_tool if {
	result := dangerous_commands.deny with input as {
		"tool_name": "Write",
		"tool_input": {"file_path": "/tmp/foo.lua", "content": "hello"},
	}
	count(result) == 0
}

test_gemini_run_shell_command if {
	result := dangerous_commands.deny with input as {
		"tool_name": "run_shell_command",
		"tool_input": {"command": "rm -rf /tmp/test"},
	}
	count(result) > 0
}
