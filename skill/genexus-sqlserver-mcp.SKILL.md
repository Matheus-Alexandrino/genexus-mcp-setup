---
name: genexus-sqlserver-mcp
description: Use when reading (or, if write access was explicitly enabled, writing) SQL Server database schema or data through the SQL Server MCP server (mssql-mcp-node, server "sqlserver") for Matheus's GeneXus/ERP projects — checking real table structure/data behind a GeneXus KB backed by SQL Server.
---

# SQL Server MCP — database agent skill

The SQL Server MCP is the community npm package [`mssql-mcp-node`](https://www.npmjs.com/package/mssql-mcp-node), run via `npx -y mssql-mcp-node` over stdio, registered under the server name `sqlserver`. It plays the same role as the Oracle SQLcl MCP but for SQL Server — giving the agent access to schema and real data of a database behind a GeneXus KB, to complement what GxObjGen shows from the transaction/attribute definitions.

## Prerequisites and connection mode

- Registered via option **[6]** of `setup-genexus-mcp.ps1`, which collects server/host, port (default `1433`), database, user and password (`Read-Host -AsSecureString`, never typed visibly), and registers the stdio server in all 3 clients (Claude Code, Claude Desktop, VS Code).
- **Read-only by default.** Writing requires the environment variable `MSSQL_ENABLE_WRITES=true`, passed **only at registration time** for that one registration (unlike `GXOBJGEN_WRITE`, this is not a permanent Windows environment variable) — this is what gates the `execute_write_query` tool. If a write-type call is rejected, that's almost certainly why.
- Credentials (server, port, database, user, password) are cached **only on the local machine**, in `sqlserver.local.json` (gitignored) — reused automatically on subsequent runs of option [6] unless the dev overrides them.
- Ideally the SQL Server login used is a **dedicated, read-only account** for the agent, not an application account with broad write access — this is a recommendation from the setup script, not something the MCP enforces itself.

## Golden workflow rules

1. **List/describe tables before writing queries** — don't assume a schema; use the discovery tools first.
2. **Any write (`execute_write_query`) requires explicit user confirmation before executing** — even when `MSSQL_ENABLE_WRITES` is on for this registration, treat every write the same way GxObjGen treats KB mutations: no surprises, confirm first.
3. If `execute_write_query` isn't available or is rejected, that means writes weren't enabled at registration — don't try to work around it; tell the user to re-run option [6] and opt in to writes if that's really what's needed.
4. When investigating a card/issue that references specific data, **cross-check the real table** with this MCP instead of relying solely on the GeneXus transaction definition (GxObjGen) — same cross-referencing pattern used with the Oracle SQLcl MCP.
5. If both an Oracle SQLcl MCP (`sqlcl`) and this SQL Server MCP (`sqlserver`) are registered, don't assume which one backs a given KB — ask or check if unsure, since they can point at entirely different databases.

## Tools

Discovery/read tools (e.g. `list_tables`, `describe_table`, `execute_sql_query`) plus `execute_write_query`, available only when `MSSQL_ENABLE_WRITES=true` was set at registration. Exact tool names/schemas come from the package itself — use ToolSearch/`/mcp` to confirm the live list rather than assuming.

## Troubleshooting quick table

| Symptom | Likely cause / fix |
|---|---|
| Connection/login timeout | Wrong server/port, firewall blocking the port (default 1433), or invalid credentials — re-run option [6] with the correct values |
| `execute_write_query` missing or rejected | `MSSQL_ENABLE_WRITES` wasn't enabled at registration — re-run option [6] and answer "s" (yes) when asked about enabling writes |
| Agent doesn't see the `sqlserver` server after registering | Run `/mcp` in the open Claude Code session to reconnect |
| Wrong database/table shows up | Cached config in `sqlserver.local.json` reused an old server/database — re-run option [6] and provide new values instead of accepting the defaults |

Source: `setup-genexus-mcp.ps1` (`Install-SqlServerMcp`), [mssql-mcp-node on npm](https://www.npmjs.com/package/mssql-mcp-node).
