package cupcake.policies.neph.protected_paths_test

import rego.v1

import data.cupcake.policies.neph.protected_paths

test_block_env_file if {
	result := protected_paths.deny with input as {
		"tool_name": "Write",
		"tool_input": {"file_path": "/project/.env", "content": "SECRET=foo"},
	}
	count(result) > 0
}

test_block_env_local if {
	result := protected_paths.deny with input as {
		"tool_name": "Write",
		"tool_input": {"file_path": "/project/.env.local", "content": "SECRET=foo"},
	}
	count(result) > 0
}

test_block_credentials_json if {
	result := protected_paths.deny with input as {
		"tool_name": "Edit",
		"tool_input": {"file_path": "/project/credentials.json", "content": "{}"},
	}
	count(result) > 0
}

test_allow_normal_file if {
	result := protected_paths.deny with input as {
		"tool_name": "Write",
		"tool_input": {"file_path": "/project/src/main.lua", "content": "print('hello')"},
	}
	count(result) == 0
}

test_gemini_filepath_field if {
	result := protected_paths.deny with input as {
		"tool_name": "write_file",
		"tool_input": {"filepath": "/project/.env.production", "content": "SECRET=foo"},
	}
	count(result) > 0
}

test_block_ssh_key if {
	result := protected_paths.deny with input as {
		"tool_name": "Write",
		"tool_input": {"file_path": "/home/user/.ssh/id_rsa", "content": "key"},
	}
	count(result) > 0
}
