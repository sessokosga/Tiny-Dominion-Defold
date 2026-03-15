# Gemini AI Assistant Guidelines

## 1. Configurations & MCP Servers
- **Settings**: Always read and respect the configurations located in `.gemini/settings.json`.
- **Defold MCP**: The project runs a Defold MCP server (`defold-server`) connected via `mcp-remote` on `http://localhost:59146/mcp`. Use this capability to interact with the Defold Editor directly when relevant.

## 2. Cross-Session Memory & Context
- To maintain continuity between work sessions, a persistent state file is located at `.gemini/session_state.md`.
- **Reading**: At the beginning of complex tasks, consult `.gemini/session_state.md` to understand the current architecture and completed tasks.
- **Writing**: At the end of significant milestones or architectural changes, you **MUST update** `.gemini/session_state.md` to reflect the new state, resolved issues, and upcoming tasks.

## 3. Project Context
- **Engine**: Defold (Lua).
- **Architecture Base**: Originally prototyped in Construct 3 / TypeScript, currently being migrated to Defold.
- **Data Management**: Data is managed via CastleDB (`data.cdb`) and parsed natively in Lua.