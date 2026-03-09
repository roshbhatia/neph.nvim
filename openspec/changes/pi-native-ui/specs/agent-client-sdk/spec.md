## MODIFIED Requirements

### Requirement: Review via RPC
`NephClient` SHALL provide a `review(filePath, content)` method that opens an interactive review in Neovim and returns the user's decision by waiting for an asynchronous RPC notification.

#### Scenario: Review returns envelope
- **WHEN** `client.review("/tmp/foo.ts", "new content")` is called
- **THEN** Neovim SHALL open a vimdiff review tab
- **AND** the client SHALL wait for a `neph:review_done` notification containing the result
- **AND** the promise SHALL resolve with a `ReviewEnvelope` when the notification is received

## ADDED Requirements

### Requirement: UI interaction methods
`NephClient` SHALL provide generic `uiSelect`, `uiInput`, and `uiNotify` methods that invoke their respective Neovim RPCs and, for interactive methods, wait for a notification response.

#### Scenario: uiSelect resolves on notification
- **WHEN** `client.uiSelect("Title", ["A", "B"])` is called
- **THEN** the client SHALL invoke `ui.select`
- **AND** wait for a corresponding `neph:ui_response` notification before resolving the returned promise

#### Scenario: uiInput resolves on notification
- **WHEN** `client.uiInput("Prompt", "Default")` is called
- **THEN** the client SHALL invoke `ui.input`
- **AND** wait for a corresponding `neph:ui_response` notification before resolving the returned promise

#### Scenario: uiNotify is fire-and-forget
- **WHEN** `client.uiNotify("Message", "info")` is called
- **THEN** the client SHALL invoke `ui.notify` and resolve the promise immediately without waiting for a notification
