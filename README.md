# genexus-mcp-setup

Manual de instalação e script de setup para integrar agentes de IA (Claude Code, Claude Desktop, VS Code) à stack completa de um desenvolvedor GeneXus, via MCP, usando quatro servidores em paralelo:

- **[GxObjGen](https://github.com/franciscorizzo/GxObjGen-install)** — extensão nativa da IDE, cobre **GeneXus 15, 17 e 18**, ~73 tools (`gx_*`).
- **genexus-mcp** (pacote npm, servidor `genexus18mcp`) — community, cobre **GeneXus 18**.
- **[azure-devops-mcp](https://github.com/microsoft/azure-devops-mcp)** (pacote npm oficial da Microsoft, `@azure-devops/mcp`) — dá ao agente acesso aos **cards (work items)**, repositórios, pipelines, wiki e test plans do Azure DevOps, para cruzar o chamado com o código da KB.
- **Oracle SQLcl MCP** (CLI oficial da Oracle, modo nativo `-mcp`) — dá ao agente acesso ao **schema e aos dados reais do banco Oracle** por trás da KB (ex.: tabelas EJADE/ESAFIRA do app `bh_dsv_ejade`), sem depender de prints de SQL Developer.

Os quatro são complementares e convivem no mesmo cliente, sob nomes diferentes (`genexus`, `genexus18mcp`, `azure-devops`, `sqlcl`). Um mesmo chamado costuma envolver os quatro: o card no Azure DevOps descreve o problema, o GxObjGen mostra a definição do objeto na KB, o Oracle SQLcl confirma o dado real na tabela, e o genexus-mcp cobre o que for GX18-específico do pacote community.

## Conteúdo deste repositório

- [`setup-genexus-mcp.bat`](./setup-genexus-mcp.bat) + [`setup-genexus-mcp.ps1`](./setup-genexus-mcp.ps1) — script de setup com menu (estilo ativador): instala/registra GxObjGen, genexus-mcp, Azure DevOps MCP, Oracle SQLcl MCP, ou roda diagnóstico. Idempotente, com backup automático dos arquivos de configuração antes de qualquer edição. Instalação "mastigada": dois cliques e o resto é ir apertando Enter/colando o token quando pedido.
- [`skill/genexus-gxobjgen-mcp.SKILL.md`](./skill/genexus-gxobjgen-mcp.SKILL.md) — skill do agente para trabalhar com o MCP GxObjGen (regras de uso, catálogo de tools, diferenças por versão).
- [`skill/genexus-azuredevops-mcp.SKILL.md`](./skill/genexus-azuredevops-mcp.SKILL.md) — skill do agente para ler cards/work items, repos e wiki do Azure DevOps.
- [`skill/genexus-oracle-sqlcl-mcp.SKILL.md`](./skill/genexus-oracle-sqlcl-mcp.SKILL.md) — skill do agente para consultar schema/dados do Oracle via SQLcl.

## Visão geral

| | GxObjGen | genexus-mcp (genexus18mcp) | azure-devops-mcp | Oracle SQLcl MCP |
| --- | --- | --- | --- | --- |
| Tipo | Extensão nativa da IDE (DLL registrada em `genexus.exe`) | Pacote npm, gateway externo via `npx` | Pacote npm oficial (Microsoft), via `npx` | CLI oficial Oracle (SQLcl), modo nativo `-mcp` — **não é pacote npm** |
| Cobre | KB do GeneXus (objetos, código) | KB do GeneXus (GX18) | Cards/work items, repos, pipelines, wiki, test plans do Azure DevOps | Schema e dados reais do banco Oracle da KB |
| Versões GeneXus | 15, 17 e 18 (mesma instalação) | Apenas 18 | N/A (não depende do GeneXus) | N/A (não depende do GeneXus) |
| Tools expostas | ~71–73, prefixo `gx_*` | Conjunto próprio (community), menor | Dezenas, por área (`wit_*`, `repo_*`, `pipelines_*`, `wiki_*`, `search_*`...) | `connect`, `connections_list`, `schema_information`, `sql_run`, `sqlcl_run`, entre outras |
| Transporte | HTTP local (`127.0.0.1:8780` ou porta por KB) | stdio via `npx genexus-mcp` | stdio via `npx @azure-devops/mcp` | stdio via `sql.exe -mcp` |
| Escrita | Desabilitada por padrão; liga com `GXOBJGEN_WRITE=1` | Conforme configuração do pacote | Depende do escopo do PAT (comece só com leitura) | **Sem deny-by-default** — depende do privilégio do usuário Oracle da conexão salva |
| Origem/instalação | github.com/franciscorizzo/GxObjGen-install | pacote `genexus-mcp` no npm | github.com/microsoft/azure-devops-mcp (`@azure-devops/mcp` no npm) | Distribuído pela própria Oracle — instalação manual à parte (não é `npx`/`winget`) |

## Pré-requisitos

- **GeneXus** 15, 17 ou 18 instalado (`C:\Program Files (x86)\GeneXus\GeneXus<versão>`).
- **PowerShell** (para `install.ps1` do GxObjGen — precisa rodar como Administrador).
- **git** para clonar `GxObjGen-install` (sem git, o `.bat` baixa o ZIP).
- **Node.js/npm** com `npx` no PATH (necessário para o genexus-mcp e para o Azure DevOps MCP).
- **Claude Code CLI** no PATH (`claude mcp add`, `npx genexus-mcp clients ...`) — o próprio `.bat` oferece instalar automaticamente se não encontrar.
- **Python 3** no PATH — opcional, só necessário para o modo *gateway* do GxObjGen (porta única 8780 para múltiplas KBs). Sem Python, use o modo *per-KB* (sem dependência).
- **Personal Access Token (PAT) do Azure DevOps** — só necessário para a opção [4] (Azure DevOps MCP). Ver [Autenticação do Azure DevOps MCP](#autenticação-do-azure-devops-mcp) abaixo.
- **Oracle SQLcl instalado** (`sql.exe`, tipicamente em `C:\Oracle\sqlcl\bin\sql.exe`) e **JDK 17+** (`JAVA_HOME`) — só necessário para a opção [5] (Oracle SQLcl MCP). Ver [Conexão do Oracle SQLcl MCP](#conexão-do-oracle-sqlcl-mcp) abaixo.

## Uso rápido

1. Baixe `setup-genexus-mcp.bat` e `setup-genexus-mcp.ps1` para a mesma pasta (a pasta `skill/` é só documentação, não precisa estar junto para o script rodar).
2. Dê 2 cliques em `setup-genexus-mcp.bat`.
3. Escolha no menu:
   ```
   [1] Instalar/registrar GxObjGen (GX15/17/18)
   [2] Instalar/registrar genexus-mcp (npm, GX18)
   [3] Fazer os dois (1 + 2)
   [4] Instalar/registrar Azure DevOps MCP (PAT pessoal)
   [5] Instalar/registrar Oracle SQLcl MCP (schema/dados Oracle)
   [6] Habilitar/desabilitar escrita na KB (GXOBJGEN_WRITE)
   [7] Diagnostico / Status
   [8] Sair
   ```

O script clona `GxObjGen-install` em `C:\Tools\GxObjGen-install`, roda `install.ps1` elevado (pede UAC), detecta Python no PATH para escolher gateway ou per-KB, e registra nos clientes — Claude Code via `claude mcp add`, Claude Desktop e VS Code editando os arquivos de configuração (com backup automático antes de qualquer alteração, e checagem de idempotência: rodar de novo não duplica nem quebra o que já está lá). Se o CLI `claude` ainda não estiver instalado, o próprio script oferece instalar (instalador nativo oficial) e ajusta o PATH — inclusive o PATH permanente do Windows, avisando o sistema da mudança, para não precisar reabrir a máquina.

As opções [4] e [5] são por dev: cada pessoa gera seu próprio PAT do Azure DevOps e cria sua própria conexão Oracle — nada disso é compartilhado nem versionado no repositório (ver `.gitignore`).

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

## Autenticação do Azure DevOps MCP

O `@azure-devops/mcp` roda via `npx` (stdio). O `setup-genexus-mcp.ps1` (opção [4]) registra o servidor **apenas no Claude Code**, com `claude mcp add --transport stdio --scope user --env PERSONAL_ACCESS_TOKEN=<base64> azure-devops -- npx -y @azure-devops/mcp <org> --authentication pat`. O `--scope user` grava o token já dentro de `~/.claude.json` (fora deste repositório, específico da máquina), então não é preciso reabrir o terminal para o Claude Code enxergar o servidor — só rodar `/mcp` numa sessão já aberta para reconectar.

> Claude Desktop e VS Code não são registrados automaticamente para este MCP: como esses clientes não têm um mecanismo equivalente ao `--scope user --env` do Claude Code, a única forma de usá-los ali seria colocar o `PERSONAL_ACCESS_TOKEN` diretamente no `claude_desktop_config.json`/`mcp.json` — o que o script evita de propósito, para nunca deixar um PAT em texto puro num arquivo de configuração comum. Se precisar do Azure DevOps MCP nesses clientes, isso é uma etapa manual e consciente, fora do escopo deste `.bat`.

Passo a passo do que o script pede:

1. Cada dev entra em `https://dev.azure.com/<SUA-ORG>` (cola o dominio da empresa), clica no avatar > **Personal access tokens** > **New Token**, com escopo mínimo (ex.: Work Items Read) e prazo de expiração.
2. Cola o token quando o script pedir — a digitação não aparece na tela (`Read-Host -AsSecureString`).
3. O script monta o `PERSONAL_ACCESS_TOKEN` no formato exigido pelo pacote (base64 de `<email>:<pat>`) e registra no Claude Code.
4. O token fica salvo **só nesta máquina**, num arquivo `azure-devops.local.json` (fora do git — ver `.gitignore`), para não precisar colar de novo a cada execução; a opção reusa automaticamente se ainda for válida.

## Conexão do Oracle SQLcl MCP

O Oracle SQLcl MCP não é um pacote instalado pelo script — é o CLI oficial da Oracle (`sql`/SQLcl), que passou a ter um modo `-mcp` nativo. A opção [5] do `setup-genexus-mcp.ps1` só **detecta** o executável (`sql.exe` no PATH, no caminho padrão `C:\Oracle\sqlcl\bin\sql.exe`, ou informado manualmente) e o Java (`JAVA_HOME`/`java`, precisa de JDK 17+), e registra o servidor stdio nos 3 clientes — sem nunca pedir usuário/senha do banco.

A credencial do Oracle é tratada do mesmo jeito que o PAT do Azure DevOps: nunca entra no script nem em nenhum arquivo deste repositório. Em vez disso, cada dev roda manualmente, no próprio terminal, uma única vez:

```
sql /nolog
conn -save <nome-da-conexao> -savepwd <usuario>/<senha>@<host>:<porta>/<service_name>
```

Isso grava a conexão **criptografada no armazenamento próprio do SQLcl** (fora do `.claude.json`, fora deste repositório). O agente nunca vê a senha — só lista nomes de conexão (`connections_list`) e conecta por nome (`connect`).

> **Recomendado**: use um usuário Oracle dedicado e **somente leitura** para o agente, nunca o schema owner da aplicação. Diferente do GxObjGen (que bloqueia escrita sem `GXOBJGEN_WRITE=1`), o SQLcl MCP **não tem deny-by-default** — `sql_run`/`sqlcl_run` executam qualquer DML/DDL que o usuário da conexão tiver privilégio para rodar. A proteção real é o privilégio do usuário de banco, não o MCP.

Registro nos clientes (feito pelo script, opção [5]):

```powershell
claude mcp add --transport stdio --scope user --env JAVA_HOME=<javaHome> sqlcl -- <sqlPath> -mcp
```

```json
{
  "mcpServers": {
    "sqlcl": { "command": "<sqlPath>", "args": ["-mcp"], "env": { "JAVA_HOME": "<javaHome>" } }
  }
}
```

Nenhum segredo entra nesse JSON — só o caminho do executável e o `JAVA_HOME`.

## Habilitar escrita na KB (GXOBJGEN_WRITE)

O GxObjGen é deny-by-default: sem a variável `GXOBJGEN_WRITE=1` definida **antes** de abrir o GeneXus, o agente só consegue ler a KB. Isso costumava ser 100% manual — cada dev tinha que setar a variável por fora do script, sem nenhuma ajuda.

A opção **[6]** do `setup-genexus-mcp.ps1` resolve isso do mesmo jeito que o script já trata o PATH do Claude Code: grava `GXOBJGEN_WRITE` como variável de ambiente do **usuário** (permanente, sobrevive a reinícios) e avisa o Windows da mudança (broadcast de `WM_SETTINGCHANGE`) — sem precisar de logoff/logon. A opção também desliga a variável de novo quando rodada com a escrita já habilitada.

```powershell
[Environment]::SetEnvironmentVariable("GXOBJGEN_WRITE", "1", "User")   # habilita
[Environment]::SetEnvironmentVariable("GXOBJGEN_WRITE", $null, "User") # desabilita
```

Dois pontos importantes:

- **É opt-in, nunca automático.** A opção [6] sempre pergunta antes de habilitar, e avisa que qualquer sessão do agente (ou outra pessoa usando a mesma conta do Windows) passa a poder escrever na KB sem aviso extra enquanto a variável estiver ligada.
- **Só vale depois de fechar e reabrir o GeneXus** — o GxObjGen lê `GXOBJGEN_WRITE` uma única vez, no momento em que o `genexus.exe` inicia. Mudar a variável com o GeneXus já aberto não tem efeito até reabrir.

`Show-Status` (opção [7]) mostra o estado atual dessa variável.

## Variáveis de ambiente

| Variável | Usada por | Efeito |
| --- | --- | --- |
| `GXOBJGEN_WRITE=1` | GxObjGen | Habilita escrita na KB. Precisa estar definida **antes** de abrir o GeneXus. A opção [6] do script grava/apaga ela como variável de usuário, permanente. |
| `PERSONAL_ACCESS_TOKEN` | Azure DevOps MCP | Base64 de `<email>:<pat>` — obrigatório com `--authentication pat`. Gravado só dentro do `~/.claude.json` (escopo usuário), nunca num arquivo deste repo. |
| `JAVA_HOME` | Oracle SQLcl MCP | Precisa apontar para um JDK 17+ para o modo `-mcp` do SQLcl subir. |
| PATH: `python`/`py` | GxObjGen (modo gateway) | Sem Python, o modo gateway não sobe — use per-KB. |
| PATH: `git` | Instalação do GxObjGen | Sem git, o `.bat` baixa o ZIP do GitHub. |
| PATH: `node`/`npx` | genexus-mcp, Azure DevOps MCP | Necessário para `npx genexus-mcp@latest` e `npx @azure-devops/mcp`. |
| PATH: `sql` (ou caminho manual) | Oracle SQLcl MCP | `sql.exe` do SQLcl — instalação manual, o script só detecta. |
| PATH: `claude` | Todos | CLI usado por `claude mcp add` e `npx genexus-mcp clients add`. |

## Segurança

- **Loopback only** (`127.0.0.1`) para o GxObjGen — nada sai da máquina, nenhuma chamada externa nem upload de dados da KB.
- **Read-only por padrão** (deny-by-default) no GxObjGen — escrita liga só com `GXOBJGEN_WRITE=1`. A opção **[6]** do script grava essa variável como variável de usuário permanente (mesmo mecanismo do PATH do Claude Code) e é sempre opt-in — pergunta antes de habilitar e avisa que, enquanto ligada, qualquer sessão do agente (ou outra pessoa na mesma conta do Windows) pode escrever na KB sem aviso extra.
- Toda mutação do GxObjGen suporta `dryRun` e `idempotencyKey`.
- `gx_delete_object` / `gx_delete_cascade` são irreversíveis — exigem confirmação explícita.
- **Azure DevOps MCP sai da máquina** (fala com `dev.azure.com`) — diferente do GxObjGen. O PAT deve ter o menor conjunto de escopos possível (comece só com Work Items Read) e nunca deve ser commitado em `claude_desktop_config.json`/`mcp.json`/`.claude.json` — o script grava só como entrada de escopo usuário no Claude Code (não num arquivo versionado).
- **Oracle SQLcl MCP não tem deny-by-default**: `sql_run`/`sqlcl_run` rodam DML/DDL sem dry-run — a proteção é o privilégio do usuário Oracle da conexão salva, não o MCP. Use sempre um usuário dedicado só-leitura. Toda execução fica auditada do lado do banco (`DBTOOLS$MCP_LOG`, `V$SESSION.MODULE`/`ACTION`).
- Credenciais (PAT do Azure DevOps, senha do Oracle) nunca passam por texto visível no terminal (`-AsSecureString` / `conn -savepwd`) e nunca são versionadas — todo cache local usa o padrão `*.local.txt`/`*.local.json`, já coberto pelo `.gitignore`.

## Verificação

```powershell
npx genexus-mcp@latest clients   # registered/installed = 3
npx genexus-mcp@latest doctor --mcp-smoke   # fail deve ser 0
```

Com o GeneXus aberto e a KB carregada, peça ao agente: *"usando o GxObjGen, roda o gx_whoami"*.

Para o Azure DevOps, numa sessão do Claude Code já aberta rode `/mcp` para reconectar e peça: *"usando o Azure DevOps, lista os work items do tipo Bug atribuídos a mim"* ou *"lê o card \<id\>"*.

Para o Oracle SQLcl, depois de rodar `conn -save -savepwd` manualmente, peça ao agente: *"usando o sqlcl, roda connections_list e conecta na conexão \<nome\>"*.

## Troubleshooting

| Sintoma | MCP | Causa provável / solução |
| --- | --- | --- |
| Tools ausentes ou com schema antigo | GxObjGen / Azure DevOps / Oracle | Rodar `/mcp` no Claude Code para reconectar |
| Gateway (8780) não responde | GxObjGen | Python fora do PATH — trocar para modo per-KB ou instalar Python |
| Conexão recusada em todas as portas | GxObjGen | GeneXus fechado ou sem KB carregada |
| Escritas sempre recusadas | GxObjGen | `GXOBJGEN_WRITE` não está habilitada (rodar a opção [6] do script) ou o GeneXus não foi fechado e reaberto depois de habilitar — a variável só é lida quando o `genexus.exe` inicia |
| Extensão GX15 desabilitada silenciosamente | GxObjGen | Rodar `install.ps1` de novo (auto-corrige `PackageCompatibility`) |
| "Failed to connect" / "Access denied" | genexus-mcp | Gateway exe em `%LOCALAPPDATA%` bloqueado por AppLocker/SRP — reinstalar em caminho whitelisted |
| Cliente não aparece em `clients` | genexus-mcp | Rodar `npx genexus-mcp clients add --clients <nome>` de novo |
| `401`/`TF400813`/"Access Denied" ao ler um card | Azure DevOps | PAT expirado, sem o escopo Work Items Read, ou de outra org — gerar um novo e rodar a opção [4] do script de novo |
| Agente não vê o servidor `azure-devops` mesmo após registrar | Azure DevOps | Rodar `/mcp` na sessão do Claude Code para reconectar (não precisa reiniciar o terminal, já que o token vai no `--scope user`) |
| `sql.exe não encontrado` | Oracle SQLcl | SQLcl não está instalado ou não está no PATH/caminho padrão — instalar e rodar a opção [5] de novo informando o caminho |
| "nenhuma conexão salva" / agente não acha conexão nenhuma | Oracle SQLcl | Ninguém rodou `conn -save -savepwd` ainda nesta máquina — rodar manualmente antes de pedir ao agente para conectar |
| Modo `-mcp` do SQLcl não sobe | Oracle SQLcl | `JAVA_HOME` ausente ou apontando para um JDK incompatível — precisa de JDK 17+ |

## Referências

- [GxObjGen-install (franciscorizzo)](https://github.com/franciscorizzo/GxObjGen-install) — README, GETTING-STARTED.md, CLAUDE.md, docs/tools.md, `.claude/skills/gxobjgen/SKILL.md`.
- [genexus-mcp no npm](https://www.npmjs.com/package/genexus-mcp)
- [azure-devops-mcp (microsoft)](https://github.com/microsoft/azure-devops-mcp) — README, docs/GETTINGSTARTED.md (autenticação), docs/TOOLSET.md (catálogo de tools).
- [Oracle docs — Using the Oracle SQLcl MCP Server](https://docs.oracle.com/en/database/oracle/sql-developer-command-line/25.2/sqcug/using-oracle-sqlcl-mcp-server.html)
