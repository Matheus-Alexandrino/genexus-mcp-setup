---
name: genexus-gxobjgen-mcp
description: Use when working on a GeneXus Knowledge Base (GX15, GX17 or GX18) through the GxObjGen MCP server (tools prefixed gx_*, e.g. mcp__genexus__gx_*) — reading, creating, editing, validating, building or running KB objects for Matheus's GeneXus/ERP projects.
---

# GxObjGen MCP — GeneXus KB agent skill

GxObjGen is a native GeneXus extension (not the older `genexus-mcp` npm package / `genexus18mcp` server Matheus also has registered — that one only targets GX18 and uses a different tool prefix). GxObjGen exposes ~71-73 MCP tools, all prefixed `gx_`, over HTTP from inside a running `genexus.exe` process, and supports **GeneXus 15, 17 and 18** in the same install.

If both MCP servers are registered in the same client, use tool names to tell them apart: GxObjGen tools are `gx_*` (server "genexus"); the older community server is "genexus18mcp". Default to GxObjGen for anything that isn't GX18-only legacy work, since it's the one with multi-version support and the richer tool catalog.

## Prerequisites and connection modes

- GeneXus must be **open with the target KB** — the MCP server starts automatically with the IDE. Nothing works if GeneXus is closed or no KB is loaded.
- Two connection modes:
  - **Gateway mode** — fixed endpoint `http://127.0.0.1:8780/mcp`, serves all open KBs at once, requires **Python in PATH**. Registered under a **single** server name (`genexus`) regardless of how many KBs are open — this is exactly why the `kb=<slug>` parameter (rule 8 below) matters: the server name alone doesn't disambiguate which KB a call targets.
  - **Per-KB mode** — no Python needed, deterministic port in the 8787–8986 range, shown in GeneXus's Output panel when the KB opens (e.g. `MCP server ON em http://127.0.0.1:8845/mcp`). The Output panel also prints the exact registration command to use, with a server name in the `genexus-<kb-slug>` pattern (e.g. KB `bh_jade_new` → `claude mcp add --transport http genexus-bhjadenew http://127.0.0.1:8845/mcp`) — copy that command as shown rather than guessing the slug. Use `gx_targets` to see connected KBs and their slugs when more than one is open.
- Read-only is the default (deny-by-default security). Write operations require the user to have reopened GeneXus with `GXOBJGEN_WRITE=1` set in the environment **before launch** — never suggest a workaround if a write is refused; tell the user to relaunch GeneXus that way instead.
- Tools are deferred in Claude Code — load schemas via ToolSearch before calling one for the first time. If tools look stale or missing after an update, run `/mcp` to reconnect.

## Version differences (GX15 vs GX17/18)

GX15 support needs GxObjGen v1.12.0+. In GX15, four object-type tools are unavailable and simply won't appear: `gx_create_or_update_designsystem`, and the `_api`, `_urlrewrite`, `_usercontrol` variants. `gx_wwp_*` (WorkWithPlus) tools additionally require WorkWithPlus to be installed in that KB's GeneXus, independent of version. Everything else in the ~73-tool catalog behaves the same across GX15/17/18. When a requested object type isn't available, say so plainly rather than trying a workaround — it's a GX15 platform limitation, not a bug.

## Golden workflow rules

1. **Start every session with `gx_whoami`** — confirms active KB, GeneXus version, and read/write mode. Don't assume; check.
2. **Orient with `gx_conventions`** (KB overview by object type/module) and `gx_search_indexed` for fast full-text search (~0.1–0.4s). Reserve the slower `gx_search_in_source` (live grep) for cases the index misses.
3. **Read large objects partially** — use `gx_get_object_text` with `part`, `fromLine`/`toLine`, or `find`+`context` instead of pulling the whole object. Then edit with `gx_edit op=replace` anchored to the found text, rather than rewriting the whole object.
4. **Creation tools are idempotent** (transactions, procedures, SDTs, data providers, web panels, menus, domains, APIs, etc.) — safe to re-run. Validate afterwards with `gx_specify` and actually read the response for errors/warnings; never report success without checking.
5. **Use `dryRun` and `idempotencyKey`** on mutations when exploring or when a step might be repeated.
6. **Deletions are irreversible** (`gx_delete_object`, `gx_delete_cascade`) — always confirm with the user first, explicitly, before calling them.
7. **Build/reorganize/run are slow** (roughly 30–150s via MSBuild) — warn the user before running `gx_reorganize`, `gx_build`, `gx_run`, `gx_test` so a long pause isn't mistaken for a hang.
8. Multi-KB setups: pass the `kb` parameter (from `gx_targets`) explicitly. This only applies in **gateway mode**, where every KB shares the same `genexus` server registration — with a single KB open, or in per-KB mode (each KB has its own port/server name), it's optional/not applicable.

## Tool catalog (by category)

- **Discovery**: `gx_whoami`, `gx_targets`, `gx_conventions`, `gx_overview`, `gx_list_objects`, `gx_search`, `gx_search_indexed`, `gx_search_in_source`, `gx_modules`, `gx_attributes`, `gx_list_object_types`
- **Create/update**: `gx_create_or_update_transaction`, `_procedure`, `_dataprovider`, `_sdt`, `_api`, `_webpanel`, `_menu`, `_domain`, `_dataselector`, `_externalobject`, `_query`, `_theme`, `_designsystem`, `_usercontrol`, `_urlrewrite`; plus `gx_create_textobject`, `gx_create_module`, `gx_create_folder`
- **Validate/build/run**: `gx_specify`, `gx_reorganize`, `gx_build`, `gx_test`, `gx_run`, `gx_datastore`, `gx_kb_check`, `gx_schema`
- **Read/analyze**: `gx_get_properties`, `gx_get_object_text`, `gx_read_structure`, `gx_analyze`, `gx_dependencies`, `gx_doc`, `gx_object_version`, `gx_history`
- **Edit/refactor**: `gx_edit`, `gx_refactor`, `gx_set_property`, `gx_set_part_property`, `gx_add_part_item`, `gx_delete_object`, `gx_delete_cascade`
- **WorkWithPlus**: `gx_apply_workwithplus`, `gx_apply_pattern`, `gx_wwp_read/get/set/add/remove`, `gx_wwp_add_tree`
- **Layout**: `gx_layout_tree`, `gx_layout_set`
- **Portability/versions**: `gx_export`, `gx_import`, `gx_version`, `gx_recipe`, `gx_msbuild` (raw MSBuild — use sparingly)
- **Introspection**: `gx_object_api`, `gx_object_parts`, `gx_prop_inspect`, `gx_var_inspect`
- **Status/meta**: `gx_gxserver`, `gx_gam`, `gx_telemetry`

## Troubleshooting quick table

| Symptom | Likely cause / fix |
|---|---|
| Tools missing or old schema | Run `/mcp` to reconnect |
| Gateway (8780) doesn't respond | Python missing from PATH — switch to per-KB mode or install Python |
| Connection refused on all ports | GeneXus isn't open, or no KB is loaded in it |
| Writes always rejected | GeneXus wasn't relaunched with `GXOBJGEN_WRITE=1` |
| GX15 extension silently disabled | Re-run `install.ps1` — it auto-corrects PackageCompatibility mismatches |
| Multiple KBs open, wrong one edited | Use `gx_targets` for slugs, pass `kb=<slug>` explicitly |

Source: github.com/franciscorizzo/GxObjGen-install (README, GETTING-STARTED.md, CLAUDE.md, docs/tools.md, .claude/skills/gxobjgen/SKILL.md).
