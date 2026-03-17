# METADATA
# scope: package
# custom:
#   routing:
#     required_events: ["PreToolUse", "BeforeTool"]
#     required_tools: ["Write", "Edit", "write_file", "edit_file", "replace"]
#     required_signals: ["neph_review"]
package cupcake.policies.neph.review

import rego.v1

# Allow when neph review signal accepts
allow contains decision if {
	input.signals.neph_review.decision == "accept"
	decision := {
		"rule_id": "NEPH-REVIEW-ACCEPT",
		"reason": "Interactive review accepted all changes",
	}
}

# Modify (partial accept) — pass through merged content
modify contains decision if {
	input.signals.neph_review.decision == "partial"
	input.signals.neph_review.content != ""
	decision := {
		"rule_id": "NEPH-REVIEW-PARTIAL",
		"reason": "Interactive review partially accepted changes",
		"updated_input": {"content": input.signals.neph_review.content},
	}
}

# Deny when neph review signal rejects
deny contains decision if {
	input.signals.neph_review.decision == "reject"
	decision := {
		"rule_id": "NEPH-REVIEW-REJECT",
		"reason": sprintf("Interactive review rejected: %s", [object.get(input.signals.neph_review, "reason", "User rejected changes")]),
	}
}

# Fallback: if signal data is missing (timeout/error), ask for manual approval
ask contains decision if {
	write_or_edit_tool
	not input.signals.neph_review
	decision := {
		"rule_id": "NEPH-REVIEW-FALLBACK",
		"reason": "Interactive review unavailable — manual approval required",
		"question": "The neph review signal did not respond. Allow this file write?",
	}
}

write_or_edit_tool if {
	input.tool_name in ["Write", "Edit", "write_file", "edit_file", "replace"]
}
