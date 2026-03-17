package cupcake.policies.neph.review_test

import rego.v1

import data.cupcake.policies.neph.review

test_allow_on_accept if {
	result := review.allow with input as {
		"tool_name": "Write",
		"tool_input": {"file_path": "/tmp/foo.lua", "content": "hello"},
		"signals": {"neph_review": {"decision": "accept", "content": "hello"}},
	}
	count(result) == 1
}

test_modify_on_partial if {
	result := review.modify with input as {
		"tool_name": "Edit",
		"tool_input": {"file_path": "/tmp/foo.lua", "content": "merged"},
		"signals": {"neph_review": {"decision": "partial", "content": "merged"}},
	}
	count(result) == 1
	some d in result
	d.updated_input.content == "merged"
}

test_deny_on_reject if {
	result := review.deny with input as {
		"tool_name": "Write",
		"tool_input": {"file_path": "/tmp/foo.lua", "content": "bad"},
		"signals": {"neph_review": {"decision": "reject", "reason": "User rejected"}},
	}
	count(result) == 1
}

test_ask_when_signal_missing if {
	result := review.ask with input as {
		"tool_name": "Write",
		"tool_input": {"file_path": "/tmp/foo.lua", "content": "hello"},
		"signals": {},
	}
	count(result) == 1
}

test_no_ask_for_non_write_tool if {
	result := review.ask with input as {
		"tool_name": "Read",
		"tool_input": {"file_path": "/tmp/foo.lua"},
		"signals": {},
	}
	count(result) == 0
}

test_gemini_tool_names_recognized if {
	result := review.allow with input as {
		"tool_name": "write_file",
		"tool_input": {"filepath": "/tmp/foo.lua", "content": "hello"},
		"signals": {"neph_review": {"decision": "accept", "content": "hello"}},
	}
	count(result) == 1
}
