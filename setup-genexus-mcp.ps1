#requires -Version 5.1
<#
  setup-genexus-mcp.ps1
  Menu de setup para os MCPs do GeneXus: GxObjGen (GX15/17/18, extensao nativa)
  e genexus-mcp (pacote npm, servidor "genexus18mcp", GX18).
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
            Write-Ok "Adicionado '$localBin' ao PATH do usuario (permanente - vale em terminais novos)."
            $changed = $true
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
        claude mcp add --transport http genexus $mcpUrl
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

    if (-not (Ensure-ClaudeCodeCli)) {
        Write-Warn2 "Claude Code nao disponivel - so entrando na pasta, sem abrir o agente"
        Set-Location $kbPath
        return
    }

    Write-Info "Indo para $kbPath e abrindo o Claude Code..."
    Set-Location $kbPath
    claude
}

# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------
function Show-Menu {
    Clear-Host
    Write-Host "========================================" -ForegroundColor DarkGray
    Write-Host "  Setup MCP GeneXus - GxObjGen + genexus-mcp" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor DarkGray
    Write-Host "  [1] Instalar/registrar GxObjGen (GX15/17/18)"
    Write-Host "  [2] Instalar/registrar genexus-mcp (npm, GX18)"
    Write-Host "  [3] Fazer os dois (1 + 2)"
    Write-Host "  [4] Diagnostico / Status"
    Write-Host "  [5] Sair"
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
        "4" { Show-Status; Read-Host "Pressione Enter para voltar ao menu" | Out-Null }
        "5" { $running = $false }
        default { Write-Warn2 "Opcao invalida"; Start-Sleep -Seconds 1 }
    }
}
