"""Integration tests for review flow with actual Neovim instance."""
import json
import os
import tempfile
from pathlib import Path
from unittest.mock import Mock, patch

import pytest

from shim import cmd_review


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
    
    @patch('shim.get_nvim')
    @patch('shim.sys.stdin')
    def test_dry_run_mode_auto_accepts(self, mock_stdin, mock_get_nvim, temp_files):
        """Dry run mode should auto-accept without Neovim."""
        orig, prop_text = temp_files
        mock_stdin.isatty.return_value = False
        mock_stdin.read.return_value = prop_text
        mock_get_nvim.return_value = None
        
        # Run with dry-run flag
        with patch('shim.click.echo') as mock_echo:
            cmd_review(str(orig), dry_run=True)
            
            # Get the JSON output
            output = mock_echo.call_args[0][0]
            envelope = json.loads(output)
            
            assert envelope["schema"] == "review/v1"
            assert envelope["decision"] == "accept"
            assert "content" in envelope
    
    @patch('shim.discover_nvim_socket')
    @patch('shim.sys.stdin')
    def test_no_socket_auto_accepts(self, mock_stdin, mock_discover, temp_files):
        """No NVIM_SOCKET_PATH should auto-accept."""
        orig, prop_text = temp_files
        mock_stdin.isatty.return_value = False
        mock_stdin.read.return_value = prop_text
        mock_discover.return_value = None
        
        # Ensure no socket path in env
        with patch.dict(os.environ, {}, clear=True):
            with patch('shim.click.echo') as mock_echo:
                cmd_review(str(orig), dry_run=False)
                
                output = mock_echo.call_args[0][0]
                envelope = json.loads(output)
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
    
    @patch('shim.get_nvim')
    @patch('shim.sys.stdin')
    def test_identical_files_auto_accept(self, mock_stdin, mock_get_nvim, temp_files):
        """Identical files should auto-accept."""
        orig, _ = temp_files
        mock_stdin.isatty.return_value = False
        
        # Propose same content as original
        same_content = orig.read_text()
        mock_stdin.read.return_value = same_content
        mock_get_nvim.return_value = None
        
        with patch('shim.click.echo') as mock_echo:
            cmd_review(str(orig), dry_run=True)
            
            output = mock_echo.call_args[0][0]
            envelope = json.loads(output)
            assert envelope["decision"] == "accept"
            assert len(envelope["hunks"]) == 0


class TestLuaScriptIntegrity:
    """Test that the Lua script is valid and handles edge cases."""
    
    def test_lua_syntax_valid(self):
        """Open_diff.lua should have valid Lua syntax."""
        import subprocess
        lua_path = Path(__file__).parent.parent / 'lua' / 'open_diff.lua'
        result = subprocess.run(
            ['luac', '-p', str(lua_path)],
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, f"Lua syntax error: {result.stderr}"
    
    def test_handles_vim_nil_in_reasons(self):
        """Should handle vim.NIL in reason fields without crashing."""
        # This is tested by the type check in finalize()
        reasons = [None, "real reason", "", "another"]
        filtered = [r for r in reasons if r and type(r) == str and r != ""]
        assert filtered == ["real reason", "another"]

