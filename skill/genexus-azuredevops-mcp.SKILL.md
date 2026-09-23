---
name: genexus-azuredevops-mcp
description: Use when reading or working with Azure DevOps work items (cards), repos, pipelines, wiki or test plans through the Azure DevOps MCP server (tools prefixed by area, e.g. wit_*, repo_*, pipelines_*, wiki_* — server "azure-devops") for Matheus's GeneXus/ERP projects, e.g. cross-referencing a card with the KB object it describes.
---

# Azure DevOps MCP — work items / repos / pipelines agent skill

The Azure DevOps MCP is Microsoft's own npm package (`@azure-devops/mcp`), run via `npx` over stdio, registered under the server name `azure-devops`. It gives the agent access to a single Azure DevOps **organization** at a time (the one chosen during registration) — work items (cards), git repositories, pipelines, wiki pages and test plans. It is typically used together with GxObjGen and/or a database MCP (Oracle SQLcl / SQL Server) on the same task: the card describes the problem, GxObjGen shows the KB object, the database MCP confirms the real data.

## Prerequisites and connection mode

- Registered **only in Claude Code** (`--scope user`), via option **[4]** of `setup-genexus-mcp.ps1` — Claude Desktop and VS Code are intentionally not auto-registered for this MCP, since neither has an equivalent to `--scope user --env` and the script avoids ever writing a PAT into a plain config file (`claude_desktop_config.json`/`mcp.json`). Using this MCP from those clients is a manual, conscious step outside the script's scope.
- Authenticates with a **Personal Access Token (PAT)**, one per developer, scoped to a single org. The token is transmitted as `PERSONAL_ACCESS_TOKEN=base64(<email>:<pat>)` and stored only inside `~/.claude.json` (`--scope user`, outside this repo, per-machine) — never in a file that gets committed.
- Transport is stdio (`npx -y @azure-devops/mcp <org> --authentication pat`) — no network port, no loopback URL to worry about.
- Tools are organized by area/prefix: work items (`wit_*`), repos (`repo_*`), pipelines (`pipelines_*`), wiki (`wiki_*`), search (`search_*`), test plans, and others.

## Golden workflow rules

1. **Confirm which organization/project is in scope** before assuming — a dev may have re-registered against a different org than last time; when unsure, ask or check with a lightweight read call first.
2. **Read the card/work item before acting on it** — don't infer requirements from a card ID alone; fetch its title, description, and any linked items.
3. **Cross-reference with the KB when the card is about GeneXus code** — use GxObjGen (`gx_*`) to look at the actual object the card describes, rather than trusting the card's prose alone.
4. **Respect the PAT's scope.** The setup script's own guidance is to start PATs with read-only scopes (e.g. Work Items Read) — if a write-type call is rejected, that's very likely why; don't try to work around it, tell the user the PAT needs a broader scope reissued deliberately.
5. **Any write action (updating a work item, pushing to a repo, editing wiki) needs explicit user confirmation first** — treat these the same way GxObjGen treats KB mutations: no surprises.
6. Prefer `search_*` tools for open-ended lookups (e.g. "find the card about X") over guessing IDs.

## Troubleshooting quick table

| Symptom | Likely cause / fix |
|---|---|
| `401` / `TF400813` / "Access Denied" reading a card | PAT expired, missing the needed scope (e.g. Work Items Read), or issued for a different org — generate a new one and re-run option [4] of the setup script |
| Agent doesn't see the `azure-devops` server after registering | Run `/mcp` in the open Claude Code session to reconnect (no need to restart the terminal — the token lives in `--scope user`) |
| Works in Claude Code but not in Claude Desktop/VS Code | Expected — this MCP is only auto-registered for Claude Code by design (see Prerequisites above); registering it elsewhere is a manual step |
| Write action rejected | PAT scope is read-only (by design/recommendation) — a broader scope needs to be issued deliberately, not worked around |

Source: `setup-genexus-mcp.ps1` (`Install-AzureDevOpsMcp`), [azure-devops-mcp (microsoft)](https://github.com/microsoft/azure-devops-mcp) — README, docs/GETTINGSTARTED.md, docs/TOOLSET.md.
