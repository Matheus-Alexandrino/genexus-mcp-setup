#requires -Version 5.1
<#
  setup-genexus-mcp.ps1
  Menu de setup para a stack de MCPs do desenvolvedor GeneXus da Datainfo:
    1. GxObjGen        - GX15/17/18, extensao nativa, tools gx_*
    2. genexus-mcp     - pacote npm, servidor "genexus18mcp", GX18
    3. Azure DevOps MCP - pacote oficial @azure-devops/mcp, PAT pessoal por dev
    4. Oracle SQLcl MCP - CLI oficial Oracle (modo -mcp), schema/dados do banco
  Gerado para Matheus Alexandrino - ver manual "Manual de Instalacao - MCP GeneXus".
#>

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Configuracao
# ---------------------------------------------------------------------------
$RepoUrl    = "https://github.com/franciscorizzo/GxObjGen-install"
$RepoDir    = "C:\Tools\GxObjGen-install"
$GatewayUrl = "http://127.0.0.1:8780/mcp"

$ClaudeCodeConfig   = Join-Path $env:USERPROFILE ".claude.json"
$ClaudeDesktopConfig = Join-Path $env:APPDATA "Claude\claude_desktop_config.json"
$VSCodeConfig       = Join-Path $env:APPDATA "Code\User\mcp.json"

# Lembra a ultima pasta de KB usada, pra nao precisar redigitar toda vez.
$KbPathCache = Join-Path $PSScriptRoot "kb-path.local.txt"

# Guarda org + token do Azure DevOps de CADA DEV nesta maquina (nunca vai pro
# git - ver .gitignore - e cada um gera o proprio PAT, nao e compartilhado).
$AdoConfigCache = Join-Path $PSScriptRoot "azure-devops.local.json"

# Lembra o caminho do sql.exe (SQLcl) ja detectado/informado nesta maquina.
# Nunca guarda usuario/senha do Oracle - isso fica so no armazenamento
# criptografado proprio do SQLcl (conn -save -savepwd), fora deste repo.
$SqlPathCache = Join-Path $PSScriptRoot "sql-path.local.txt"

# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------
function Write-Info    { param([string]$Text) Write-Host "  $Text" -ForegroundColor Cyan }
function Write-Ok      { param([string]$Text) Write-Host "  $Text" -ForegroundColor Green }
function Write-Warn2   { param([string]$Text) Write-Host "  $Text" -ForegroundColor Yellow }
function Write-Err2    { param([string]$Text) Write-Host "  $Text" -ForegroundColor Red }

function Test-CommandExists {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-PythonAvailable {
    return (Test-CommandExists "python") -or (Test-CommandExists "pythonw") -or (Test-CommandExists "py")
}

$script:ClaudeCodeChecked = $false

# Garante que a pasta do instalador nativo (%USERPROFILE%\.local\bin) esta no
# PATH do USUARIO (persistente no Windows, nao so nesta sessao) e tambem no
# PATH desta sessao. Sem isso, "claude" funciona no terminal que rodou o
# instalador mas some de novo em qualquer terminal novo/outro.
# Avisa o Windows (broadcast WM_SETTINGCHANGE) que as variaveis de ambiente
# mudaram. Sem isso, o Explorer/Windows Terminal continuam com o PATH antigo
# em cache e um terminal novo aberto a partir deles herda o valor velho,
# MESMO com o registro ja atualizado - e exatamente o sintoma de "gravei no
# PATH mas o sistema ainda nao reconhece".
function Broadcast-EnvironmentChange {
    try {
        if (-not ([System.Management.Automation.PSTypeName]"Win32.NativeMethods").Type) {
            Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@ -ErrorAction Stop
        }
        $HWND_BROADCAST   = [IntPtr]0xffff
        $WM_SETTINGCHANGE = 0x1A
        $result = [UIntPtr]::Zero
        [Win32.NativeMethods]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero, "Environment", 2, 5000, [ref]$result) | Out-Null
    }
    catch {
        # Nao critico - na pior das hipoteses so precisa abrir um terminal novo depois de logoff/logon.
    }
}

function Add-ClaudeLocalBinToPath {
    $localBin = Join-Path $env:USERPROFILE ".local\bin"
    if (-not (Test-Path $localBin)) { return $false }

    $changed = $false

    # PATH desta sessao (efeito imediato, sem reabrir terminal).
    if ($env:PATH -notlike "*$localBin*") {
        $env:PATH = "$localBin;$env:PATH"
        $changed = $true
    }

    # PATH persistente do usuario (vale pra terminais novos, inclusive apos
    # reiniciar a maquina) - e o que faltava: o instalador nativo so cobre a
    # sessao em que ele mesmo roda.
    try {
        $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        if ($userPath -notlike "*$localBin*") {
            $newUserPath = if ([string]::IsNullOrEmpty($userPath)) { $localBin } else { "$userPath;$localBin" }
            [Environment]::SetEnvironmentVariable("PATH", $newUserPath, "User")
            Broadcast-EnvironmentChange
            Write-Ok "Adicionado '$localBin' ao PATH do usuario (permanente) e avisado o Windows da mudanca."
            Write-Warn2 "Se o proximo terminal (aberto pelo Explorer/menu Iniciar) ainda nao reconhecer 'claude', feche TODAS as janelas de terminal abertas (nao so a aba) e abra uma nova - ou faca logoff/logon."
            $changed = $true
        }
        else {
            # Ja estava gravado no registro de uma execucao anterior, mas o
            # terminal atual pode ter aberto ANTES desse ajuste - reforca o
            # broadcast pra qualquer terminal novo pegar o valor certo.
            Broadcast-EnvironmentChange
        }
    }
    catch {
        Write-Warn2 "Nao consegui gravar o PATH permanente do usuario ($_). 'claude' vai funcionar so nesta sessao; adicione manualmente depois: Propriedades do Sistema > Variaveis de Ambiente > PATH do usuario > $localBin"
    }

    return $changed
}

# Garante que o CLI 'claude' (Claude Code) esta disponivel nesta sessao do
# PowerShell. Se nao estiver, oferece instalar via instalador nativo oficial
# (https://claude.ai/install.ps1) e adiciona a pasta do binario ao PATH -
# tanto desta sessao quanto de forma permanente (PATH do usuario), pra nao
# precisar reconfigurar isso manualmente depois.

# Caminho fixo do binario nativo instalado por install.ps1 (claude.ai).
function Get-ClaudeExePath {
    $exe = Join-Path $env:USERPROFILE ".local\bin\claude.exe"
    if (Test-Path $exe) { return $exe }
    return $null
}

# Roda o Claude Code de forma resiliente, sem depender de o PATH ja ter
# propagado nesta sessao/terminal: tenta 'claude' do PATH primeiro e, se nao
# achar (mesmo tendo acabado de instalar), cai pro caminho completo do
# binario. Assim, dentro do proprio fluxo do script ("um clique, um Enter"),
# nunca da "termo nao reconhecido" - so um terminal aberto por fora, depois
# de instalado, pode precisar do ajuste de PATH permanente (ja tratado acima).
function Invoke-Claude {
    if (Test-CommandExists "claude") {
        claude @args
        return
    }
    $exe = Get-ClaudeExePath
    if ($exe) {
        & $exe @args
        return
    }
    Write-Err2 "Claude Code nao encontrado (nem no PATH, nem no local padrao de instalacao)."
}

function Ensure-ClaudeCodeCli {
    if ($script:ClaudeCodeChecked) { return (Test-CommandExists "claude") }
    $script:ClaudeCodeChecked = $true

    # Mesmo se 'claude' ja existir no PATH desta sessao (ou o binario nativo
    # ja estiver instalado de uma execucao anterior), garante que o PATH
    # permanente do usuario tambem aponta pra la - e exatamente o caso de
    # "instalei, funcionou uma vez, sumiu no terminal novo".
    Add-ClaudeLocalBinToPath | Out-Null

    if (Test-CommandExists "claude") { return $true }

    Write-Warn2 "CLI 'claude' (Claude Code) nao encontrado no PATH."
    $answer = Read-Host "  Instalar agora via instalador nativo oficial (irm https://claude.ai/install.ps1)? (s/N)"
    if ($answer -ne "s") {
        Write-Warn2 "Ok, pulando instalacao do Claude Code. Registros que dependem dele serao pulados."
        return $false
    }

    Write-Info "Instalando Claude Code (irm https://claude.ai/install.ps1 | iex)..."
    try {
        Invoke-Expression (Invoke-RestMethod "https://claude.ai/install.ps1")
    }
    catch {
        Write-Err2 "Falha ao rodar o instalador: $_"
        return $false
    }

    # Instalador nativo coloca o binario em $env:USERPROFILE\.local\bin\claude.exe;
    # adiciona ao PATH desta sessao E ao PATH permanente do usuario, pra nao
    # sumir de novo em outro terminal.
    Add-ClaudeLocalBinToPath | Out-Null

    if (Test-CommandExists "claude") {
        Write-Ok "Claude Code instalado e disponivel (nesta sessao e em terminais novos)."
        return $true
    }
    else {
        Write-Warn2 "Instalador rodou, mas 'claude' ainda nao aparece no PATH desta sessao. Abra um terminal NOVO (o PATH permanente ja foi ajustado) e tente de novo."
        return $false
    }
}

function Backup-ConfigFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backup = "$Path.bak-$stamp"
    Copy-Item -Path $Path -Destination $backup -Force
    return $backup
}

# Insere/atualiza um servidor MCP num arquivo JSON, de forma idempotente.
# $TopKey: "mcpServers" (Claude Code / Desktop) ou "servers" (VS Code)
# $EntryValue: hashtable com os campos do servidor (command/args OU type/url)
function Set-McpServerEntry {
    param(
        [string]$ConfigPath,
        [string]$TopKey,
        [string]$ServerKey,
        [hashtable]$EntryValue,
        [string]$ClientLabel,
        [string]$WingetId = $null
    )

    if (-not (Test-Path $ConfigPath)) {
        Write-Warn2 "$ClientLabel - config nao encontrado ($ConfigPath) - pulando"
        if ($WingetId -and (Test-CommandExists "winget")) {
            $answer = Read-Host "  $ClientLabel parece nao estar instalado. Instalar agora via winget? (s/N)"
            if ($answer -eq "s") {
                Write-Info "Instalando $ClientLabel via winget ($WingetId)..."
                winget install --id $WingetId --silent --accept-package-agreements --accept-source-agreements
                Write-Warn2 "Abra o $ClientLabel uma vez (pra ele criar o arquivo de config) e rode esta opcao de novo pra registrar o MCP."
            }
        }
        elseif ($WingetId) {
            Write-Warn2 "winget nao encontrado nesta maquina - instale o $ClientLabel manualmente e rode esta opcao de novo."
        }
        return
    }

    $raw = Get-Content -Path $ConfigPath -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $json = New-Object PSObject
    }
    else {
        try {
            $json = $raw | ConvertFrom-Json
        }
        catch {
            Write-Err2 "$ClientLabel - nao consegui interpretar o JSON existente ($ConfigPath) - pulando por seguranca"
            return
        }
    }

    if (-not $json.PSObject.Properties[$TopKey]) {
        $json | Add-Member -NotePropertyName $TopKey -NotePropertyValue (New-Object PSObject)
    }

    if ($json.$TopKey.PSObject.Properties[$ServerKey]) {
        Write-Info "$ClientLabel - '$ServerKey' ja registrado - nada a fazer"
        return
    }

    $backup = Backup-ConfigFile -Path $ConfigPath
    $entry = New-Object PSObject
    foreach ($k in $EntryValue.Keys) {
        $entry | Add-Member -NotePropertyName $k -NotePropertyValue $EntryValue[$k]
    }
    $json.$TopKey | Add-Member -NotePropertyName $ServerKey -NotePropertyValue $entry

    ($json | ConvertTo-Json -Depth 20) | Set-Content -Path $ConfigPath -Encoding UTF8
    if ($backup) {
        Write-Ok "$ClientLabel - registrado (backup em $backup)"
    }
    else {
        Write-Ok "$ClientLabel - registrado"
    }
}

# ---------------------------------------------------------------------------
# Opcao 1: GxObjGen
# ---------------------------------------------------------------------------
function Install-GxObjGen {
    Write-Host ""
    Write-Host "== GxObjGen (GX15 / GX17 / GX18) ==" -ForegroundColor Magenta

    $genexusRunning = Get-Process -Name "genexus" -ErrorAction SilentlyContinue
    if ($genexusRunning) {
        Write-Warn2 "O GeneXus esta aberto. Feche-o antes de continuar (o instalador exige isso)."
        $answer = Read-Host "  Fechar manualmente e pressionar Enter para continuar, ou digite 'c' para cancelar"
        if ($answer -eq "c") { return }
    }

    if (Test-CommandExists "git") {
        if (Test-Path (Join-Path $RepoDir ".git")) {
            Write-Info "Repositorio ja existe em $RepoDir - atualizando (git pull)"
            Push-Location $RepoDir
            git pull --ff-only
            Pop-Location
        }
        else {
            Write-Info "Clonando $RepoUrl em $RepoDir"
            New-Item -ItemType Directory -Path (Split-Path $RepoDir -Parent) -Force | Out-Null
            git clone $RepoUrl $RepoDir
        }
    }
    else {
        Write-Warn2 "git nao encontrado no PATH - baixando ZIP do GitHub"
        $zipPath = Join-Path $env:TEMP "GxObjGen-install.zip"
        Invoke-WebRequest -Uri "$RepoUrl/archive/refs/heads/main.zip" -OutFile $zipPath
        $extractDir = Join-Path $env:TEMP "GxObjGen-install-extract"
        if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
        Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
        $inner = Get-ChildItem -Path $extractDir -Directory | Select-Object -First 1
        New-Item -ItemType Directory -Path (Split-Path $RepoDir -Parent) -Force | Out-Null
        if (Test-Path $RepoDir) { Remove-Item $RepoDir -Recurse -Force }
        Move-Item -Path $inner.FullName -Destination $RepoDir
    }

    $installScript = Join-Path $RepoDir "install.ps1"
    if (-not (Test-Path $installScript)) {
        Write-Err2 "install.ps1 nao encontrado em $RepoDir - abortando esta opcao"
        return
    }

    # O install.ps1 do GxObjGen so detecta instalacoes nos caminhos padrao
    # (C:\Program Files (x86)\GeneXus\GeneXus15\17\18). Se nenhuma delas
    # existir, pede a pasta manualmente e repassa via -GxDir.
    $standardPaths = @(
        "C:\Program Files (x86)\GeneXus\GeneXus15",
        "C:\Program Files (x86)\GeneXus\GeneXus17",
        "C:\Program Files (x86)\GeneXus\GeneXus18"
    ) | Where-Object { Test-Path (Join-Path $_ "genexus.exe") }

    $installArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$installScript`"")
    if (-not $standardPaths) {
        Write-Warn2 "Nenhuma instalacao padrao do GeneXus encontrada em Program Files."
        $customPath = Read-Host "  Informe a pasta onde fica o genexus.exe (ex.: C:\GX\15u12)"
        if ($customPath -and (Test-Path (Join-Path $customPath "genexus.exe"))) {
            $installArgs += @("-GxDir", "`"$customPath`"")
        }
        else {
            Write-Err2 "Nao encontrei genexus.exe em '$customPath' - abortando esta opcao"
            return
        }
    }

    Write-Info "Rodando install.ps1 como Administrador (UAC vai pedir confirmacao)..."
    $proc = Start-Process -FilePath "powershell.exe" `
        -ArgumentList $installArgs `
        -Verb RunAs -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Warn2 "install.ps1 terminou com codigo $($proc.ExitCode) - confira a saida da janela elevada"
    }
    else {
        Write-Ok "install.ps1 concluido"
    }

    $hasPython = Test-PythonAvailable
    if ($hasPython) {
        Write-Info "Python encontrado no PATH - usando modo gateway ($GatewayUrl)"
        $mcpUrl = $GatewayUrl
    }
    else {
        Write-Warn2 "Python nao encontrado no PATH - modo gateway (porta 8780) nao vai subir."
        Write-Warn2 "Abra o GeneXus com a KB, veja a porta per-KB no painel Output e registre manualmente:"
        Write-Warn2 "  claude mcp add --transport http genexus-<kb> http://127.0.0.1:<porta>/mcp"
        Write-Warn2 "Pulando o registro automatico nos 3 clientes para o GxObjGen."
        return
    }

    if (Ensure-ClaudeCodeCli) {
        Write-Info "Registrando no Claude Code..."
        Invoke-Claude mcp add --transport http genexus $mcpUrl
    }
    else {
        Write-Warn2 "Pulando registro no Claude Code (CLI nao instalado)"
    }

    # Claude Desktop nao aceita "url" nativo em claude_desktop_config.json;
    # usa o wrapper mcp-remote (via npx) para servidores HTTP.
    Set-McpServerEntry -ConfigPath $ClaudeDesktopConfig -TopKey "mcpServers" -ServerKey "genexus" `
        -EntryValue @{ command = "npx"; args = @("mcp-remote", $mcpUrl) } -ClientLabel "Claude Desktop" `
        -WingetId "Anthropic.Claude"

    # VS Code usa "servers" + {type, url} nativamente.
    Set-McpServerEntry -ConfigPath $VSCodeConfig -TopKey "servers" -ServerKey "genexus" `
        -EntryValue @{ type = "http"; url = $mcpUrl } -ClientLabel "VS Code" `
        -WingetId "Microsoft.VisualStudioCode"

    Write-Host ""
    Write-Ok "GxObjGen configurado. Abra o GeneXus com a KB e peca 'gx_whoami' para confirmar."
    Write-Info "Por padrao a escrita na KB fica desligada - use a opcao [6] do menu quando precisar habilitar."
}

# ---------------------------------------------------------------------------
# Opcao 2: genexus-mcp (npm)
# ---------------------------------------------------------------------------
function Install-GenexusMcp {
    Write-Host ""
    Write-Host "== genexus-mcp (npm, GX18) ==" -ForegroundColor Magenta

    if (-not (Test-CommandExists "npx")) {
        Write-Err2 "npx nao encontrado no PATH (Node.js instalado?) - abortando esta opcao"
        return
    }

    Ensure-ClaudeCodeCli | Out-Null

    $clients = @("claude-code", "claude-desktop-win", "vscode")
    foreach ($client in $clients) {
        Write-Info "Registrando genexus-mcp em '$client'..."
        npx genexus-mcp@latest clients add --clients $client
    }
    Write-Ok "genexus-mcp registrado (ou ja estava) nos 3 clientes."
}

# ---------------------------------------------------------------------------
# Opcao 4: Diagnostico
# ---------------------------------------------------------------------------
function Show-Status {
    Write-Host ""
    Write-Host "== Diagnostico ==" -ForegroundColor Magenta

    if (Test-CommandExists "npx") {
        Write-Info "genexus-mcp status:"
        npx genexus-mcp@latest status
        Write-Host ""
        Write-Info "genexus-mcp doctor --mcp-smoke:"
        npx genexus-mcp@latest doctor --mcp-smoke
    }
    else {
        Write-Warn2 "npx nao encontrado - pulando diagnostico do genexus-mcp"
    }

    Write-Host ""
    Write-Info "Testando gateway do GxObjGen ($GatewayUrl)..."
    try {
        $resp = Invoke-WebRequest -Uri $GatewayUrl -Method Post -TimeoutSec 3 -ErrorAction Stop
        Write-Ok "Gateway respondeu (HTTP $($resp.StatusCode)) - GxObjGen parece ativo"
    }
    catch {
        Write-Warn2 "Gateway nao respondeu em 127.0.0.1:8780 - normal se o GeneXus estiver fechado, sem KB aberta, ou se voce estiver em modo per-KB"
    }

    Write-Host ""
    Write-Info "Testando Oracle SQLcl (sql.exe)..."
    $sqlCheck = $null
    if (Test-CommandExists "sql") {
        $sqlCheck = (Get-Command "sql" -ErrorAction SilentlyContinue).Source
    }
    elseif (Test-Path $SqlPathCache) {
        $cached = (Get-Content -Path $SqlPathCache -Raw -ErrorAction SilentlyContinue).Trim()
        if ($cached -and (Test-Path $cached)) { $sqlCheck = $cached }
    }
    if ($sqlCheck) {
        Write-Ok "sql.exe resolvido em: $sqlCheck"
        Write-Info "Peca ao agente pra rodar 'connections_list' (ferramenta do MCP sqlcl) pra ver as conexoes salvas - o script nao mexe nisso."
    }
    else {
        Write-Warn2 "sql.exe nao encontrado (nem no PATH, nem em cache) - rode a opcao [5] do menu para configurar"
    }

    Write-Host ""
    Write-Info "Escrita na KB (GXOBJGEN_WRITE)..."
    $writeMode = [Environment]::GetEnvironmentVariable("GXOBJGEN_WRITE", "User")
    if ($writeMode -eq "1") {
        Write-Warn2 "HABILITADA nesta conta - o agente pode criar/editar/apagar objetos na KB. Use a opcao [6] para desligar."
    }
    else {
        Write-Ok "Desabilitada (leitura por padrao) - use a opcao [6] do menu para habilitar quando precisar."
    }
}

# ---------------------------------------------------------------------------
# Passo final: ir pra pasta da KB e abrir o Claude Code
# ---------------------------------------------------------------------------
function Open-KbAndLaunchClaude {
    Write-Host ""
    $answer = Read-Host "  Ir para a pasta da KB e rodar 'claude' agora? (s/N)"
    if ($answer -ne "s") { return }

    $default = $null
    if (Test-Path $KbPathCache) {
        $default = (Get-Content -Path $KbPathCache -Raw -ErrorAction SilentlyContinue).Trim()
    }

    if ($default) {
        $kbPath = Read-Host "  Pasta da KB [Enter para usar '$default']"
        if ([string]::IsNullOrWhiteSpace($kbPath)) { $kbPath = $default }
    }
    else {
        $kbPath = Read-Host "  Pasta da KB (ex.: C:\KBs\MinhaKB ou C:\gx\15u12)"
    }

    if ([string]::IsNullOrWhiteSpace($kbPath) -or -not (Test-Path $kbPath)) {
        Write-Err2 "Pasta '$kbPath' nao encontrada - pulando"
        return
    }

    Set-Content -Path $KbPathCache -Value $kbPath -Encoding UTF8 -NoNewline

    $claudeOk = (Ensure-ClaudeCodeCli) -or (Get-ClaudeExePath)
    if (-not $claudeOk) {
        Write-Warn2 "Claude Code nao disponivel - so entrando na pasta, sem abrir o agente"
        Set-Location $kbPath
        return
    }

    Write-Info "Indo para $kbPath e abrindo o Claude Code..."
    Set-Location $kbPath
    Invoke-Claude
}

# ---------------------------------------------------------------------------
# Opcao 4: Azure DevOps MCP (pacote oficial @azure-devops/mcp, autenticacao
# por PAT - cada dev gera o proprio token, o script so guarda local nesta
# maquina e registra no Claude Code)
# ---------------------------------------------------------------------------
function Install-AzureDevOpsMcp {
    Write-Host ""
    Write-Host "== Azure DevOps MCP ==" -ForegroundColor Magenta

    if (-not (Test-CommandExists "npx")) {
        Write-Err2 "npx nao encontrado no PATH (Node.js instalado?) - abortando esta opcao"
        return
    }

    Write-Info "Cada dev precisa do proprio Personal Access Token (PAT) do Azure DevOps:"
    Write-Info "  1. Entre em https://dev.azure.com/<SUA-ORG> logado com sua conta"
    Write-Info "  2. Clique no seu avatar (canto superior direito) > 'Personal access tokens'"
    Write-Info "  3. 'New Token' - de um nome, escopo minimo (ex.: Code=Read, Work Items=Read) e prazo de expiracao"
    Write-Info "  4. Copie o token gerado (so aparece uma vez!) e cole aqui quando for pedido"
    Write-Host ""

    $cached = $null
    if (Test-Path $AdoConfigCache) {
        try { $cached = Get-Content -Path $AdoConfigCache -Raw -ErrorAction Stop | ConvertFrom-Json }
        catch { $cached = $null }
    }

    # Org padrao da empresa - qualquer dev pode so dar Enter, a menos que
    # esteja apontando pra outra org do Azure DevOps.
    $defaultOrg = if ($cached) { $cached.org } else { "DATAINFOLABS" }
    $org = Read-Host "  Organizacao do Azure DevOps [Enter para usar '$defaultOrg']"
    if ([string]::IsNullOrWhiteSpace($org)) { $org = $defaultOrg }
    if ([string]::IsNullOrWhiteSpace($org)) {
        Write-Err2 "Organizacao nao informada - abortando esta opcao"
        return
    }

    $reusePat = $false
    if ($cached -and $cached.patB64 -and $cached.org -eq $org) {
        $answer = Read-Host "  Ja tem um PAT salvo nesta maquina pra essa org - reusar? (S/n)"
        if ($answer -ne "n") { $reusePat = $true }
    }

    if ($reusePat) {
        $patB64 = $cached.patB64
        $email = $cached.email
    }
    else {
        $email = Read-Host "  Seu e-mail (identifica o token, pode ser qualquer valor nao-vazio)"
        if ([string]::IsNullOrWhiteSpace($email)) { $email = "dev@local" }

        $securePat = Read-Host "  Cole o Personal Access Token (PAT)" -AsSecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePat)
        try {
            $patPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }
        finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }

        if ([string]::IsNullOrWhiteSpace($patPlain)) {
            Write-Err2 "PAT nao informado - abortando esta opcao"
            return
        }

        # Formato exigido pelo @azure-devops/mcp: PERSONAL_ACCESS_TOKEN deve
        # conter o base64 de "<email>:<pat>".
        $patB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$email`:$patPlain"))
        $patPlain = $null
    }

    # So fica salvo NESTA maquina (arquivo *.local.* - fora do git, ver
    # .gitignore). Ainda e sensivel (da acesso ao Azure DevOps do dev),
    # trate como senha.
    @{ org = $org; email = $email; patB64 = $patB64 } | ConvertTo-Json | Set-Content -Path $AdoConfigCache -Encoding UTF8

    Ensure-ClaudeCodeCli | Out-Null

    Write-Info "Registrando 'azure-devops' no Claude Code (escopo: usuario - vale em qualquer pasta/projeto)..."
    try { Invoke-Claude mcp remove azure-devops --scope user 2>$null | Out-Null } catch {}
    Invoke-Claude mcp add --transport stdio --scope user --env "PERSONAL_ACCESS_TOKEN=$patB64" azure-devops -- npx -y "@azure-devops/mcp" $org --authentication pat

    Write-Host ""
    Write-Ok "Azure DevOps MCP registrado para a org '$org'."
    Write-Warn2 "Token salvo so localmente em '$AdoConfigCache' - se o PAT expirar ou trocar de maquina, rode esta opcao de novo."
    Write-Warn2 "Se ja tinha uma sessao do Claude Code aberta, rode '/mcp' nela pra reconectar e ver as tools novas (nao precisa reiniciar o terminal)."
}

# ---------------------------------------------------------------------------
# Opcao 5: Oracle SQLcl MCP (CLI oficial da Oracle, modo nativo -mcp, stdio -
# da acesso ao schema/dados do Oracle por tras da KB, ex.: tabelas EJADE/
# ESAFIRA usadas pelo app bh_dsv_ejade). Nao e pacote npm: e pre-requisito
# manual (SQLcl + JDK 17+ instalados a parte). O script SO detecta o
# executavel e registra o servidor - nunca pede nem guarda usuario/senha do
# Oracle, isso fica so no armazenamento criptografado do proprio SQLcl
# (comando "conn -save -savepwd", rodado manualmente pelo dev).
# ---------------------------------------------------------------------------
function Install-OracleSqlclMcp {
    Write-Host ""
    Write-Host "== Oracle SQLcl MCP ==" -ForegroundColor Magenta

    # 1) Detectar sql.exe: PATH -> caminho padrao -> cache local -> perguntar.
    $sqlPath = $null
    if (Test-CommandExists "sql") {
        $sqlPath = (Get-Command "sql" -ErrorAction SilentlyContinue).Source
    }

    if (-not $sqlPath) {
        $defaultSqlPath = "C:\Oracle\sqlcl\bin\sql.exe"
        if (Test-Path $defaultSqlPath) { $sqlPath = $defaultSqlPath }
    }

    $cachedSqlPath = $null
    if (Test-Path $SqlPathCache) {
        $cachedSqlPath = (Get-Content -Path $SqlPathCache -Raw -ErrorAction SilentlyContinue).Trim()
    }
    if (-not $sqlPath -and $cachedSqlPath -and (Test-Path $cachedSqlPath)) {
        $sqlPath = $cachedSqlPath
    }

    if (-not $sqlPath) {
        Write-Warn2 "sql.exe (Oracle SQLcl) nao encontrado no PATH nem em '$defaultSqlPath'."
        $manualPath = Read-Host "  Informe o caminho completo do sql.exe (ex.: C:\Oracle\sqlcl\bin\sql.exe)"
        if ([string]::IsNullOrWhiteSpace($manualPath) -or -not (Test-Path $manualPath)) {
            Write-Err2 "Caminho '$manualPath' nao encontrado - instale o SQLcl (Oracle) e rode esta opcao de novo. Abortando esta opcao."
            return
        }
        $sqlPath = $manualPath
    }
    else {
        Write-Ok "sql.exe encontrado em: $sqlPath"
    }

    Set-Content -Path $SqlPathCache -Value $sqlPath -Encoding UTF8 -NoNewline

    # 2) Detectar Java (SQLcl -mcp roda sobre JVM, precisa JDK 17+). So avisa,
    # nao aborta - o dev pode ja ter um JAVA_HOME valido que o script nao
    # detecta perfeitamente.
    $javaHome = $env:JAVA_HOME
    if ($javaHome -and (Test-Path $javaHome)) {
        Write-Ok "JAVA_HOME encontrado: $javaHome"
    }
    elseif (Test-CommandExists "java") {
        Write-Warn2 "JAVA_HOME nao esta setado, mas 'java' foi encontrado no PATH - o SQLcl deve funcionar mesmo assim."
        Write-Warn2 "Se o modo -mcp falhar ao subir, defina JAVA_HOME apontando pra um JDK 17+ e rode esta opcao de novo."
        $javaHome = $null
    }
    else {
        Write-Warn2 "Nenhum JDK detectado (nem JAVA_HOME, nem 'java' no PATH). O modo -mcp do SQLcl precisa de JDK 17+."
        Write-Warn2 "Instale um JDK 17+ e defina JAVA_HOME antes de usar este MCP - continuando o registro mesmo assim."
        $javaHome = $null
    }

    # 3) Credencial do banco: NUNCA pedida/guardada pelo script. So imprime o
    # comando pra rodar manualmente, no terminal do proprio dev - mesmo
    # raciocinio do PAT do Azure DevOps.
    Write-Host ""
    Write-Info "Autenticacao no Oracle: o SQLcl guarda a conexao de forma CRIPTOGRAFADA no seu"
    Write-Info "proprio armazenamento (fora deste repositorio, fora do .claude.json). O agente"
    Write-Info "nunca ve sua senha - so lista/usa conexoes salvas por nome."
    Write-Info "Se ainda nao tem uma conexao salva, rode manualmente num terminal (fora deste script):"
    Write-Host ""
    Write-Host "    sql /nolog" -ForegroundColor White
    Write-Host "    conn -save <nome-da-conexao> -savepwd <usuario>/<senha>@<host>:<porta>/<service_name>" -ForegroundColor White
    Write-Host ""
    Write-Warn2 "Recomendado: use um usuario Oracle dedicado e SOMENTE LEITURA para o agente,"
    Write-Warn2 "nunca o schema owner da aplicacao - o SQLcl MCP nao tem deny-by-default (sql_run"
    Write-Warn2 "executa DML/DDL se o usuario da conexao tiver privilegio pra isso)."
    Write-Host ""

    # 4) Registrar o servidor stdio nos 3 clientes - mesmo padrao idempotente
    # ja usado pros outros MCPs. Nenhum segredo entra no JSON: so caminho do
    # executavel e JAVA_HOME.
    Ensure-ClaudeCodeCli | Out-Null

    $envArgs = @()
    if ($javaHome) { $envArgs = @("--env", "JAVA_HOME=$javaHome") }

    Write-Info "Registrando 'sqlcl' no Claude Code (escopo: usuario - vale em qualquer pasta/projeto)..."
    try { Invoke-Claude mcp remove sqlcl --scope user 2>$null | Out-Null } catch {}
    Invoke-Claude mcp add --transport stdio --scope user @envArgs sqlcl -- $sqlPath -mcp

    $desktopEnv = @{}
    $vscodeEnv = @{}
    if ($javaHome) {
        $desktopEnv = @{ JAVA_HOME = $javaHome }
        $vscodeEnv = @{ JAVA_HOME = $javaHome }
    }

    $desktopEntry = @{ command = $sqlPath; args = @("-mcp") }
    if ($desktopEnv.Count -gt 0) { $desktopEntry["env"] = $desktopEnv }
    Set-McpServerEntry -ConfigPath $ClaudeDesktopConfig -TopKey "mcpServers" -ServerKey "sqlcl" `
        -EntryValue $desktopEntry -ClientLabel "Claude Desktop" -WingetId "Anthropic.Claude"

    $vscodeEntry = @{ type = "stdio"; command = $sqlPath; args = @("-mcp") }
    if ($vscodeEnv.Count -gt 0) { $vscodeEntry["env"] = $vscodeEnv }
    Set-McpServerEntry -ConfigPath $VSCodeConfig -TopKey "servers" -ServerKey "sqlcl" `
        -EntryValue $vscodeEntry -ClientLabel "VS Code" -WingetId "Microsoft.VisualStudioCode"

    Write-Host ""
    Write-Ok "Oracle SQLcl MCP registrado (executavel: $sqlPath)."
    Write-Warn2 "Se ainda nao criou a conexao salva, rode o 'conn -save -savepwd' acima antes de usar."
    Write-Warn2 "Depois, peca ao agente pra rodar 'connections_list' pra confirmar o que esta disponivel."
    Write-Warn2 "Se ja tinha uma sessao do Claude Code aberta, rode '/mcp' nela pra reconectar e ver as tools novas (nao precisa reiniciar o terminal)."
}

# ---------------------------------------------------------------------------
# Opcao 6: habilita/desabilita escrita na KB do GxObjGen (GXOBJGEN_WRITE=1).
# Por padrao o GxObjGen e deny-by-default: sem essa variavel, o agente so
# le a KB. Antes isso era 100% manual (o dev tinha que setar a variavel
# fora do script); agora o script grava/apaga ela como variavel de ambiente
# do USUARIO (igual faz com o PATH do Claude Code) e avisa o Windows da
# mudanca (broadcast) - so falta fechar e reabrir o GeneXus pra valer, ja
# que o GxObjGen so le essa variavel no momento em que o genexus.exe inicia.
# ---------------------------------------------------------------------------
function Set-GxObjGenWriteMode {
    Write-Host ""
    Write-Host "== Escrita na KB (GXOBJGEN_WRITE) ==" -ForegroundColor Magenta

    $current = [Environment]::GetEnvironmentVariable("GXOBJGEN_WRITE", "User")
    $isEnabled = ($current -eq "1")

    if ($isEnabled) {
        Write-Info "Escrita esta HABILITADA nesta conta do Windows (GXOBJGEN_WRITE=1)."
        $answer = Read-Host "  Desabilitar agora e voltar para leitura por padrao? (s/N)"
        if ($answer -eq "s") {
            [Environment]::SetEnvironmentVariable("GXOBJGEN_WRITE", $null, "User")
            Broadcast-EnvironmentChange
            Write-Ok "Escrita desabilitada (GXOBJGEN_WRITE removida)."
            Write-Warn2 "Feche e reabra o GeneXus para a mudanca valer - a variavel so e lida quando o genexus.exe inicia."
        }
        else {
            Write-Info "Mantido como esta - escrita continua habilitada."
        }
        return
    }

    Write-Warn2 "Por padrao a escrita na KB fica DESLIGADA (deny-by-default) - o agente so consegue"
    Write-Warn2 "criar/editar/apagar objetos com GXOBJGEN_WRITE=1 definida ANTES de abrir o GeneXus."
    Write-Warn2 "Habilitar isso permanentemente nesta conta aumenta o risco: qualquer sessao do agente"
    Write-Warn2 "(ou de outra pessoa usando esta conta do Windows) podera escrever na KB sem aviso extra."
    $answer = Read-Host "  Habilitar escrita agora (GXOBJGEN_WRITE=1, permanente nesta conta)? (s/N)"
    if ($answer -ne "s") {
        Write-Info "Ok, mantendo leitura por padrao."
        return
    }

    [Environment]::SetEnvironmentVariable("GXOBJGEN_WRITE", "1", "User")
    Broadcast-EnvironmentChange
    Write-Ok "GXOBJGEN_WRITE=1 gravada como variavel de ambiente do usuario (permanente) e o Windows foi avisado da mudanca."
    Write-Warn2 "Feche e reabra o GeneXus para a mudanca valer - a variavel so e lida quando o genexus.exe inicia."
    Write-Warn2 "Para desligar de novo, rode esta opcao [6] outra vez."
}

# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------
function Show-Menu {
    Clear-Host
    Write-Host "========================================" -ForegroundColor DarkGray
    Write-Host "  Setup MCP GeneXus - Datainfo" -ForegroundColor White
    Write-Host "  GxObjGen + genexus-mcp + Azure DevOps + Oracle SQLcl" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor DarkGray
    Write-Host "  [1] Instalar/registrar GxObjGen (GX15/17/18)"
    Write-Host "  [2] Instalar/registrar genexus-mcp (npm, GX18)"
    Write-Host "  [3] Fazer os dois (1 + 2)"
    Write-Host "  [4] Instalar/registrar Azure DevOps MCP (PAT pessoal)"
    Write-Host "  [5] Instalar/registrar Oracle SQLcl MCP (schema/dados Oracle)"
    Write-Host "  [6] Habilitar/desabilitar escrita na KB (GXOBJGEN_WRITE)"
    Write-Host "  [7] Diagnostico / Status"
    Write-Host "  [8] Sair"
    Write-Host "========================================" -ForegroundColor DarkGray
}

$running = $true
while ($running) {
    Show-Menu
    $choice = Read-Host "Escolha uma opcao"
    switch ($choice) {
        "1" { Install-GxObjGen; Open-KbAndLaunchClaude; Read-Host "Pressione Enter para voltar ao menu" | Out-Null }
        "2" { Install-GenexusMcp; Open-KbAndLaunchClaude; Read-Host "Pressione Enter para voltar ao menu" | Out-Null }
        "3" { Install-GxObjGen; Install-GenexusMcp; Open-KbAndLaunchClaude; Read-Host "Pressione Enter para voltar ao menu" | Out-Null }
        "4" { Install-AzureDevOpsMcp; Read-Host "Pressione Enter para voltar ao menu" | Out-Null }
        "5" { Install-OracleSqlclMcp; Read-Host "Pressione Enter para voltar ao menu" | Out-Null }
        "6" { Set-GxObjGenWriteMode; Read-Host "Pressione Enter para voltar ao menu" | Out-Null }
        "7" { Show-Status; Read-Host "Pressione Enter para voltar ao menu" | Out-Null }
        "8" { $running = $false }
        default { Write-Warn2 "Opcao invalida"; Start-Sleep -Seconds 1 }
    }
}
