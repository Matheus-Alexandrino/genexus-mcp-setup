# genexus-mcp-setup

Manual de instalação e script de setup para integrar agentes de IA (Claude Code, Claude Desktop, VS Code) a Knowledge Bases do GeneXus via MCP, usando dois servidores em paralelo:

- **[GxObjGen](https://github.com/franciscorizzo/GxObjGen-install)** — extensão nativa da IDE, cobre **GeneXus 15, 17 e 18**, ~73 tools (`gx_*`).
- **genexus-mcp** (pacote npm, servidor `genexus18mcp`) — community, cobre **GeneXus 18**.

## Conteúdo deste repositório

- [`setup-genexus-mcp.bat`](./setup-genexus-mcp.bat) + [`setup-genexus-mcp.ps1`](./setup-genexus-mcp.ps1) — script de setup com menu (estilo ativador): instala/registra GxObjGen, genexus-mcp, os dois, ou roda diagnóstico. Idempotente, com backup automático dos arquivos de configuração antes de qualquer edição.
- [`skill/genexus-gxobjgen-mcp.SKILL.md`](./skill/genexus-gxobjgen-mcp.SKILL.md) — a skill usada pelo agente de IA para trabalhar com o MCP GxObjGen (regras de uso, catálogo de tools, diferenças por versão).

## Visão geral

| | GxObjGen | genexus-mcp (genexus18mcp) |
| --- | --- | --- |
| Tipo | Extensão nativa da IDE (DLL registrada em `genexus.exe`) | Pacote npm, gateway externo via `npx` |
| Versões GeneXus | 15, 17 e 18 (mesma instalação) | Apenas 18 |
| Tools expostas | ~71–73, prefixo `gx_*` | Conjunto próprio (community), menor |
| Transporte | HTTP local (`127.0.0.1:8780` ou porta por KB) | stdio via `npx genexus-mcp` |
| Escrita na KB | Desabilitada por padrão; liga com `GXOBJGEN_WRITE=1` | Conforme configuração do pacote |
| Repositório | github.com/franciscorizzo/GxObjGen-install | pacote `genexus-mcp` no npm |

Os dois são complementares, não concorrentes: registram-se sob nomes diferentes (`genexus` e `genexus18mcp`) e convivem no mesmo cliente. GxObjGen é o caminho recomendado para qualquer trabalho que precise rodar em GX15 ou GX17, e também cobre GX18 com um catálogo de tools maior.

## Pré-requisitos

- **GeneXus** 15, 17 ou 18 instalado (`C:\Program Files (x86)\GeneXus\GeneXus<versão>`).
- **PowerShell** (para `install.ps1` do GxObjGen — precisa rodar como Administrador).
- **git** para clonar `GxObjGen-install` (sem git, o `.bat` baixa o ZIP).
- **Node.js/npm** com `npx` no PATH (necessário para o genexus-mcp).
- **Claude Code CLI** no PATH (`claude mcp add`, `npx genexus-mcp clients ...`).
- **Python 3** no PATH — opcional, só necessário para o modo *gateway* do GxObjGen (porta única 8780 para múltiplas KBs). Sem Python, use o modo *per-KB* (sem dependência).

## Uso rápido

1. Baixe `setup-genexus-mcp.bat` e `setup-genexus-mcp.ps1` para a mesma pasta.
2. Dê 2 cliques em `setup-genexus-mcp.bat`.
3. Escolha no menu:
   ```
   [1] Instalar/registrar GxObjGen (GX15/17/18)
   [2] Instalar/registrar genexus-mcp (npm, GX18)
   [3] Fazer os dois (1 + 2)
   [4] Diagnostico / Status
   [5] Sair
   ```

O script clona `GxObjGen-install` em `C:\Tools\GxObjGen-install`, roda `install.ps1` elevado (pede UAC), detecta Python no PATH para escolher gateway ou per-KB, e registra nos 3 clientes — Claude Code via `claude mcp add`, Claude Desktop e VS Code editando os arquivos de configuração (com backup automático antes de qualquer alteração, e checagem de idempotência: rodar de novo não duplica nem quebra o que já está lá).

## Instalação manual do GxObjGen

```powershell
git clone https://github.com/franciscorizzo/GxObjGen-install
powershell -ExecutionPolicy Bypass -File install.ps1
```

O script detecta automaticamente GX15/17/18 instalados e copia o DLL correto para cada versão (há uma variante específica `Packages\gx15\GxObjGen.dll`). Também corrige incompatibilidades de `PackageCompatibility` — se a extensão aparecer desabilitada após uma atualização do GeneXus, rodar `install.ps1` de novo resolve.

## Registro do MCP nos clientes

**Claude Code** (modo gateway, precisa de Python no PATH):
```powershell
claude mcp add --transport http genexus http://127.0.0.1:8780/mcp
```

**Claude Desktop** — `claude_desktop_config.json` não aceita um campo `url` nativo para servidores HTTP; o `.bat` usa o wrapper [`mcp-remote`](https://www.npmjs.com/package/mcp-remote):
```json
{
  "mcpServers": {
    "genexus": { "command": "npx", "args": ["mcp-remote", "http://127.0.0.1:8780/mcp"] }
  }
}
```

**VS Code** — `mcp.json` usa `servers` + `type`/`url` nativamente:
```json
{
  "servers": {
    "genexus": { "type": "http", "url": "http://127.0.0.1:8780/mcp" }
  }
}
```

## Variáveis de ambiente

| Variável | Usada por | Efeito |
| --- | --- | --- |
| `GXOBJGEN_WRITE=1` | GxObjGen | Habilita escrita na KB. Precisa estar definida **antes** de abrir o GeneXus. |
| PATH: `python`/`py` | GxObjGen (modo gateway) | Sem Python, o modo gateway não sobe — use per-KB. |
| PATH: `git` | Instalação do GxObjGen | Sem git, o `.bat` baixa o ZIP do GitHub. |
| PATH: `node`/`npx` | genexus-mcp | Necessário para `npx genexus-mcp@latest`. |
| PATH: `claude` | Ambos | CLI usado por `claude mcp add` e `npx genexus-mcp clients add`. |

## Segurança

- **Loopback only** (`127.0.0.1`) — nada sai da máquina, nenhuma chamada externa nem upload de dados da KB.
- **Read-only por padrão** (deny-by-default) — escrita liga só com `GXOBJGEN_WRITE=1`.
- Toda mutação do GxObjGen suporta `dryRun` e `idempotencyKey`.
- `gx_delete_object` / `gx_delete_cascade` são irreversíveis — exigem confirmação explícita.

## Verificação

```powershell
npx genexus-mcp@latest clients   # registered/installed = 3
npx genexus-mcp@latest doctor --mcp-smoke   # fail deve ser 0
```

Com o GeneXus aberto e a KB carregada, peça ao agente: *"usando o GxObjGen, roda o gx_whoami"*.

## Troubleshooting

| Sintoma | MCP | Causa provável / solução |
| --- | --- | --- |
| Tools ausentes ou com schema antigo | GxObjGen | Rodar `/mcp` no Claude Code para reconectar |
| Gateway (8780) não responde | GxObjGen | Python fora do PATH — trocar para modo per-KB ou instalar Python |
| Conexão recusada em todas as portas | GxObjGen | GeneXus fechado ou sem KB carregada |
| Escritas sempre recusadas | GxObjGen | GeneXus não foi reaberto com `GXOBJGEN_WRITE=1` definida antes do lançamento |
| Extensão GX15 desabilitada silenciosamente | GxObjGen | Rodar `install.ps1` de novo (auto-corrige `PackageCompatibility`) |
| "Failed to connect" / "Access denied" | genexus-mcp | Gateway exe em `%LOCALAPPDATA%` bloqueado por AppLocker/SRP — reinstalar em caminho whitelisted |
| Cliente não aparece em `clients` | genexus-mcp | Rodar `npx genexus-mcp clients add --clients <nome>` de novo |

## Referências

- [GxObjGen-install (franciscorizzo)](https://github.com/franciscorizzo/GxObjGen-install) — README, GETTING-STARTED.md, CLAUDE.md, docs/tools.md, `.claude/skills/gxobjgen/SKILL.md`.
- [genexus-mcp no npm](https://www.npmjs.com/package/genexus-mcp)
