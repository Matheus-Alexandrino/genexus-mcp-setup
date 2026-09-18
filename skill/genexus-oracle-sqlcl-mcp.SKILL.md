---
name: genexus-oracle-sqlcl-mcp
description: Use when reading Oracle database schema or data through the SQLcl MCP server (tools such as connect, connections_list, schema_information, sql_run, sqlcl_run — server "sqlcl") for Matheus's GeneXus/ERP projects, e.g. checking the real structure/data behind KB transactions (EJADE/ESAFIRA tables used by bh_dsv_ejade).
---

# Oracle SQLcl MCP — database agent skill

The SQLcl MCP is Oracle's own CLI (`sql`/SQLcl) running in native `-mcp` mode (stdio transport), **not** an npm package. It gives the agent read/write access to the Oracle database behind a GeneXus KB — useful to check the real table structure and actual data, complementing what GxObjGen shows from the GeneXus transaction/attribute definitions. When investigating an Azure DevOps card that cites a specific record, use this MCP to check the real table (e.g. EJADE/ESAFIRA) instead of inferring only from the transaction definition in GeneXus.

## How it differs from the other MCPs in this stack

- **No deny-by-default.** Unlike GxObjGen (blocked writes without `GXOBJGEN_WRITE=1`), `sql_run`/`sqlcl_run` execute any SQL/PL-SQL — including DML and DDL — if the Oracle user behind the saved connection has the privilege. There is no dry-run mode built into this MCP.
- **Credentials never pass through the agent or this repo.** Authentication is a SQLcl "saved connection" (`conn -save <nome> -savepwd <usuario>/<senha>@<host>:<porta>/<service>`), stored encrypted in SQLcl's own local storage. The agent only ever sees connection *names* via `connections_list` — never a password.
- **Every session is audited on the database side** — `DBTOOLS$MCP_LOG` and `V$SESSION.MODULE`/`V$SESSION.ACTION` identify traffic coming from an MCP/LLM session.
- Ideally the saved connection points to a **dedicated, read-only Oracle user** — never the application's schema owner. That's a manual DBA step, done outside this MCP and outside this repo.

## Golden workflow rules

1. **Always `connections_list` before `connect`** — never guess or assume a saved connection's name.
2. **Always `schema_information` right after connecting**, before writing SQL or answering anything about the database structure — don't rely on memory or on the GeneXus KB definition alone.
3. Use `sql_run` for ordinary SQL/PL-SQL. Use `sqlcl_run` for SQLcl-specific commands (Liquibase, AWR reports, DDL generation, `LOAD`, APEX export, etc.).
4. **Any DML/DDL requires the user's explicit confirmation before executing** — there is no dry-run/deny-by-default safety net here like there is in GxObjGen, so this confirmation step is the only guard.
5. If more than one saved connection could be relevant, **ask which one to use** rather than assuming.
6. When investigating an Azure DevOps card that references specific data, **cross-check the real table** with this MCP instead of relying solely on the GeneXus transaction definition (GxObjGen) — GeneXus, Azure DevOps and Oracle MCPs complement each other when working the same ticket.

## Tools

`connect`, `connections_list`, `disconnect`, `request_status`, `schema_information`, `skills_sync`, `sql_run`, `sqlcl_run`, `annotation_generate`.

## Troubleshooting quick table

| Symptom | Likely cause / fix |
|---|---|
| `sql.exe` not found | SQLcl not installed, or not on PATH / at the default `C:\Oracle\sqlcl\bin\sql.exe` — install it and re-run option [5] of `setup-genexus-mcp.ps1` |
| No connections in `connections_list` | Nobody has run `conn -save -savepwd` yet on this machine — run it manually (`sql /nolog`, then `conn -save ...`) before asking the agent to connect |
| `-mcp` mode fails to start | Missing/incompatible JDK — SQLcl needs JDK 17+; check `JAVA_HOME` |
| Agent can run DML/DDL it shouldn't | The saved connection's Oracle user has write privileges — use a dedicated read-only user for agent work, not the app's schema owner |
| Need to audit what the agent ran | Query `DBTOOLS$MCP_LOG` and `V$SESSION.MODULE`/`V$SESSION.ACTION` on the database |

Source: `mcp__sqlcl__*` tool descriptions; [Oracle docs — Using the Oracle SQLcl MCP Server](https://docs.oracle.com/en/database/oracle/sql-developer-command-line/25.2/sqcug/using-oracle-sqlcl-mcp-server.html).
