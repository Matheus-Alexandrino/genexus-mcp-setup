---
name: genexus-jira-mcp
description: Use when reading or working with Jira issues (and, incidentally, Confluence pages or Bitbucket repos) through the official Atlassian remote MCP server (server "atlassian") for Matheus's GeneXus/ERP projects, e.g. cross-referencing a Jira issue with the KB object or database it describes.
---

# Atlassian MCP (Jira) — issue tracker agent skill

The Atlassian MCP is Atlassian's own **remote, hosted** MCP server (`https://mcp.atlassian.com/v2/mcp`) — nothing runs locally, and there is no PAT or password managed by the setup script. It gives the agent access to whatever the authenticated Atlassian account can see: Jira issues/projects primarily, plus Confluence pages and Bitbucket repos if the org uses them. It plays the same "external tracker" role in this stack that the Azure DevOps MCP plays for teams on Azure DevOps instead of Jira — usually only one of the two is actually in active use for a given project.

## Prerequisites and connection mode

- Registered via option **[7]** of `setup-genexus-mcp.ps1` in all 3 clients (Claude Code via `--transport http`, Claude Desktop via the `mcp-remote` npx wrapper, VS Code natively) — but registering is **not** the same as authenticating.
- **Authentication is OAuth 2.1 in the browser**, per developer, happening the first time a tool is actually called (typically triggered by running `/mcp` in an open Claude Code session and following the login prompt). There is nothing to paste into the script or into any config file — if asked to authenticate any other way, that's wrong.
- The agent's access mirrors the authenticated account's own permissions exactly — no elevated or shared "service account" is created by this setup.
- If the OAuth session expires or the dev switches machines/profiles, re-running `/mcp` and logging in again is the fix — never try to work around an auth failure by looking for a stored token (there isn't one).

## Golden workflow rules

1. **Never assume authentication already happened** — if a Jira tool call fails or returns nothing, the first thing to check is whether OAuth login was completed (`/mcp` + browser login), not a bug in the query.
2. **Read the issue before acting on it** — fetch its full description/status/comments rather than inferring from the key or title alone.
3. **Cross-reference with the KB when the issue is about GeneXus code** — use GxObjGen (`gx_*`) to inspect the actual object the issue describes, and the relevant database MCP (Oracle SQLcl / SQL Server) to check real data, the same cross-referencing pattern used with Azure DevOps cards.
4. **Any write action (commenting, transitioning, editing an issue) needs explicit user confirmation first** — the agent's Jira permissions are exactly the human's, so a write here is as real and visible to the team as if the human did it.
5. If both Azure DevOps and Atlassian MCPs are registered, don't assume which tracker a given project actually uses — ask if unsure rather than guessing based on which MCP happens to be configured.

## Troubleshooting quick table

| Symptom | Likely cause / fix |
|---|---|
| Agent keeps asking to authenticate | OAuth session expired, or switched machine/Claude profile — run `/mcp` again and redo the browser login |
| Agent sees no projects/issues at all | The authenticated Atlassian account lacks access to that site/project — check with the Jira admin, this isn't a script/config problem |
| Registered but tools don't show up | Run `/mcp` to reconnect, or confirm registration actually completed (re-run option [7] of the setup script) |
| Works in Claude Code but not Claude Desktop | Claude Desktop needs the `mcp-remote` wrapper (`npx mcp-remote <url>`) and `npx`/Node.js available — confirm Node is installed |

Source: `setup-genexus-mcp.ps1` (`Install-JiraMcp`), [Atlassian Remote MCP Server (official docs)](https://www.atlassian.com/platform/remote-mcp-server).
