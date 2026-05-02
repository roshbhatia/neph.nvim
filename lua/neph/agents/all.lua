return {
  require("neph.agents.amp"),
  require("neph.agents.claude"),
  -- Peer-mode claude: requires coder/claudecode.nvim. Falls back gracefully
  -- with a one-time notification if the peer plugin isn't installed.
  require("neph.agents.claude-peer"),
  require("neph.agents.codex"),
  require("neph.agents.copilot"),
  require("neph.agents.crush"),
  require("neph.agents.cursor"),
  require("neph.agents.gemini"),
  require("neph.agents.goose"),
  require("neph.agents.opencode"),
  -- Peer-mode opencode: requires nickjvandyke/opencode.nvim. Falls back
  -- gracefully with a one-time notification if the peer plugin isn't installed.
  require("neph.agents.opencode-peer"),
  require("neph.agents.pi"),
}
