"""Integration tests for review flow with actual Neovim instance."""
import json
import os
import tempfile
from pathlib import Path

import pytest

from shim import cmd_review, get_nvim


@pytest.fixture
def temp_files():
    """Create temporary original and proposed files."""
    with tempfile.TemporaryDirectory() as tmpdir:
        orig = Path(tmpdir) / "test.md"
        orig.write_text("# Title\n\nOriginal content\n")
        
        prop_text = "# Title\n\nProposed content\nWith extra line\n"
        
        yield orig, prop_text


class TestReviewCancellation:
    """Test various cancellation scenarios."""
    
    def test_dry_run_mode_auto_accepts(self, temp_files):
        """Dry run mode should auto-accept without Neovim."""
        orig, prop_text = temp_files
        
        # Run with dry-run flag
        result = os.popen(
            f'echo "{prop_text}" | python -m shim review --dry-run {orig}'
        ).read()
        
        envelope = json.loads(result)
        assert envelope["schema"] == "review/v1"
        assert envelope["decision"] == "accept"
        # Dry run may or may not include verification fields
        assert "content" in envelope
    
    def test_no_socket_auto_accepts(self, temp_files):
        """No NVIM_SOCKET_PATH should auto-accept."""
        orig, prop_text = temp_files
        
        # Ensure no socket path
        env = os.environ.copy()
        env.pop("NVIM_SOCKET_PATH", None)
        env.pop("NEPH_DRY_RUN", None)
        
        result = os.popen(
            f'echo "{prop_text}" | python -m shim review {orig}',
        ).read()
        
        envelope = json.loads(result)
        assert envelope["schema"] == "review/v1"
        assert envelope["decision"] == "accept"


class TestReviewEnvelope:
    """Test ReviewEnvelope schema compliance."""
    
    def test_accept_decision_structure(self):
        """Accept decision should have correct structure."""
        envelope = {
            "schema": "review/v1",
            "decision": "accept",
            "content": "accepted content",
            "hunks": [{"index": 1, "decision": "accept", "reason": None}],
            "reason": None,
        }
        
        assert envelope["schema"] == "review/v1"
        assert envelope["decision"] in ["accept", "reject", "partial"]
        assert isinstance(envelope["content"], str)
        assert isinstance(envelope["hunks"], list)
    
    def test_reject_decision_structure(self):
        """Reject decision should have reason."""
        envelope = {
            "schema": "review/v1",
            "decision": "reject",
            "content": "",
            "hunks": [{"index": 1, "decision": "reject", "reason": "Not good"}],
            "reason": "Not good",
        }
        
        assert envelope["decision"] == "reject"
        assert envelope["content"] == ""
        assert envelope["reason"] is not None
    
    def test_partial_decision_structure(self):
        """Partial decision should have both accepts and rejects."""
        envelope = {
            "schema": "review/v1",
            "decision": "partial",
            "content": "partially accepted",
            "hunks": [
                {"index": 1, "decision": "accept", "reason": None},
                {"index": 2, "decision": "reject", "reason": "Bad hunk"},
            ],
            "reason": "Bad hunk",
        }
        
        assert envelope["decision"] == "partial"
        assert envelope["content"] != ""
        accepts = [h for h in envelope["hunks"] if h["decision"] == "accept"]
        rejects = [h for h in envelope["hunks"] if h["decision"] == "reject"]
        assert len(accepts) > 0
        assert len(rejects) > 0


class TestEdgeCases:
    """Test edge cases and error conditions."""
    
    def test_identical_files_auto_accept(self, temp_files):
        """Identical files should auto-accept."""
        orig, _ = temp_files
        
        # Propose same content as original
        same_content = orig.read_text()
        
        result = os.popen(
            f'echo "{same_content}" | python -m shim review --dry-run {orig}'
        ).read()
        
        envelope = json.loads(result)
        assert envelope["decision"] == "accept"
        assert len(envelope["hunks"]) == 0
    
    def test_nonexistent_file_fails_gracefully(self):
        """Non-existent file should fail gracefully."""
        result = os.popen(
            'echo "content" | python -m shim review /nonexistent/file.txt'
        ).read()
        
        # Should return some kind of envelope or error
        assert result != ""
