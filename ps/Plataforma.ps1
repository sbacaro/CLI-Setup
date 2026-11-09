# ps/Plataforma.ps1 — onde cada app guarda a configuração, por sistema.
#
# Esta é a camada que a versão bash não tinha: ela assumia macOS e escrevia em
# caminhos de macOS. No Windows os caminhos são outros, e escrever no lugar
# errado falha em silêncio — o app simplesmente ignora o arquivo.
#
# Cada caminho abaixo foi conferido na documentação oficial de cada app:
#   Claude Desktop 3P: %LOCALAPPDATA%\Claude-3p\        (Windows)
#                      ~/Library/Application Support/Claude-3p/  (macOS)
#                      ~/.config/Claude-3p/              (Linux)
#   OpenCode:          ~/.config/opencode/  em todas as plataformas (xdg-basedir)
#   Codex/ChatGPT:     ~/.codex/            em todas as plataformas

Set-StrictMode -Version Latest

function Test-Windows {
    return ($PSVersionTable.Platform -eq 'Win32NT') -or ($env:OS -eq 'Windows_NT')
}

function Test-MacOS {
    if (Test-Windows) { return $false }
    return ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::OSX))
}

function Test-Linux {
    if (Test-Windows) { return $false }
    if (Test-MacOS) { return $false }
    return $true
}

# Nome de exibição do sistema, para mensagens.
function Get-OSNome {
    if (Test-Windows) { return 'Windows' }
    if (Test-MacOS) { return 'macOS' }
    return 'Linux'
}

# Raiz do perfil do usuário. No Windows o HOME do bash do Git não é o mesmo
# que o USERPROFILE do app, então usamos USERPROFILE quando existir.

# Monta caminho com o separador da plataforma. [IO.Path]::Combine usa o
# separador de quem executa, então segmentos com "/" ficariam misturados com
# "\" no Windows. Este helper troca para o separador certo.
function Join-Caminho {
    param([Parameter(Mandatory)][string]$Base, [Parameter(Mandatory)][string]$Parte)
    # O separador segue a forma da base, não a plataforma que executa: assim o
    # caminho de outro SO pode ser montado (é o que os testes fazem) e no
    # Windows real o resultado sai com "\".
    if ($Base -match '^[A-Za-z]:' -or $Base -match '\\') { $sep = '\' }
    else { $sep = [IO.Path]::DirectorySeparatorChar }
    $p = $Parte -replace '[\\/]', $sep
    return ($Base.TrimEnd('/', '\') + $sep + $p.TrimStart('/', '\'))
}

function Get-HomeRaiz {
    if (Test-Windows) {
        if ($env:USERPROFILE) { return $env:USERPROFILE }
        if ($env:HOMEDRIVE -and $env:HOMEPATH) { return "$($env:HOMEDRIVE)$($env:HOMEPATH)" }
    }
    return [Environment]::GetFolderPath('UserProfile')
}

function Get-LocalAppData {
    if ($env:LOCALAPPDATA) { return $env:LOCALAPPDATA }
    return (Join-Caminho -Base (Get-HomeRaiz) -Parte 'AppData\Local')
}

function Get-AppData {
    if ($env:APPDATA) { return $env:APPDATA }
    return (Join-Caminho -Base (Get-HomeRaiz) -Parte 'AppData\Roaming')
}

# ── Claude Desktop (modo 3P) ────────────────────────────────────────────────
# O sufixo "-3p" é literal. É ele que separa a config do modo de terceiros da
# config do app normal, e é o diretório que o app lê quando roda em 3P.
function Get-Claude3pDir {
    if (Test-Windows) {
        # Versões novas usam LOCALAPPDATA. Versões antigas usaram APPDATA
        # (Roaming) e o app migra na primeira execução; se o diretório antigo
        # existe e o novo não, é sinal de instalação antiga que ainda não migrou.
        $novo = Join-Caminho -Base (Get-LocalAppData) -Parte 'Claude-3p'
        $velho = Join-Caminho -Base (Get-AppData) -Parte 'Claude-3p'
        if (-not (Test-Path -LiteralPath $novo) -and (Test-Path -LiteralPath $velho)) {
            return $velho
        }
        return $novo
    }
    if (Test-MacOS) {
        return (Join-Caminho -Base (Get-HomeRaiz) -Parte 'Library/Application Support/Claude-3p')
    }
    return (Join-Caminho -Base (Get-HomeRaiz) -Parte '.config/Claude-3p')
}

function Get-Claude3pConfigLibrary {
    return ([IO.Path]::Combine((Get-Claude3pDir), 'configLibrary'))
}

# Diretório de plugins de organização. Exige privilégio de administrador para
# escrever, então só é exibido como informação — o configurador não escreve lá.
function Get-OrgPluginsDir {
    if (Test-Windows) { return 'C:\Program Files\Claude\org-plugins' }
    if (Test-MacOS) { return '/Library/Application Support/Claude/org-plugins' }
    return '/opt/claude/org-plugins'
}

# ── Codex / ChatGPT Desktop ─────────────────────────────────────────────────
function Get-CodexDir {
    if ($env:CODEX_HOME) { return $env:CODEX_HOME }
    return (Join-Caminho -Base (Get-HomeRaiz) -Parte '.codex')
}

function Get-CodexConfig {
    return (Join-Caminho -Base (Get-CodexDir) -Parte 'config.toml')
}

# ── Claude Code ─────────────────────────────────────────────────────────────
function Get-ClaudeCodeSettings {
    return (Join-Caminho -Base (Get-HomeRaiz) -Parte '.claude/settings.json')
}

# ── OpenCode ────────────────────────────────────────────────────────────────
# O OpenCode resolve `~/.config/opencode` em todas as plataformas; no Windows
# isso é C:\Users\<nome>\.config\opencode. Não é %APPDATA% — essa confusão é
# comum e faz a config não ser lida.
function Get-OpenCodeDir {
    if ($env:XDG_CONFIG_HOME) { return (Join-Caminho -Base $env:XDG_CONFIG_HOME -Parte 'opencode') }
    return (Join-Caminho -Base (Get-HomeRaiz) -Parte '.config/opencode')
}

function Get-OpenCodeConfig {
    return (Join-Caminho -Base (Get-OpenCodeDir) -Parte 'opencode.json')
}

function Get-OpenCodeKeyFile {
    return (Join-Caminho -Base (Get-OpenCodeDir) -Parte 'kodeo-api-key')
}

# ── Detecção de instalação ──────────────────────────────────────────────────
# Cada app tem uma forma própria de existir no disco. O que não pode acontecer
# é um app instalado aparecer como "não encontrado" porque o código só olhou
# para o caminho de um sistema.

# Claude Desktop: no macOS é um .app; no Windows é um pacote MSIX/Store, que
# não tem caminho fixo. Get-AppxPackage é o que responde de verdade.
function Test-ClaudeDesktopInstalado {
    if (Test-MacOS) {
        return (Test-Path -LiteralPath '/Applications/Claude.app') -or
               (Test-Path -LiteralPath (Join-Caminho -Base (Get-HomeRaiz) -Parte 'Applications/Claude.app'))
    }
    if (Test-Windows) {
        # O diretório de dados é criado na primeira execução em 3P; se existe,
        # o app já rodou. Mas para "instalado" o pacote é a prova melhor.
        if (Test-Path -LiteralPath (Get-Claude3pDir)) { return $true }
        try {
            $pkg = Get-AppxPackage -Name '*Claude*' -ErrorAction SilentlyContinue
            if ($pkg) { return $true }
        } catch {}
        $p = Join-Caminho -Base (Get-LocalAppData) -Parte 'AnthropicClaude'
        if (Test-Path -LiteralPath $p) { return $true }
        return $false
    }
    # Linux: pacote .deb/.rpm instala em /usr/bin ou /opt
    if (Get-Command claude-desktop -ErrorAction SilentlyContinue) { return $true }
    return (Test-Path -LiteralPath '/opt/Claude')
}

# ChatGPT Desktop: no macOS é um .app; no Windows é o app da Store (pacote
# "OpenAI.Codex" / "ChatGPT"). No Linux, AppImage ou binário no PATH.
function Get-ChatGPTApp {
    if (Test-MacOS) {
        foreach ($a in @(
            '/Applications/ChatGPT.app',
            (Join-Caminho -Base (Get-HomeRaiz) -Parte 'Applications/ChatGPT.app'),
            '/Applications/Codex.app',
            (Join-Caminho -Base (Get-HomeRaiz) -Parte 'Applications/Codex.app'))) {
            if (Test-Path -LiteralPath $a) { return $a }
        }
        return $null
    }
    if (Test-Windows) {
        try {
            $pkg = Get-AppxPackage -Name '*OpenAI*' -ErrorAction SilentlyContinue
            if (-not $pkg) { $pkg = Get-AppxPackage -Name '*ChatGPT*' -ErrorAction SilentlyContinue }
            if ($pkg) { return $pkg.PSObject.Properties['InstallLocation'].Value }
        } catch {}
        foreach ($p in @(
            (Join-Caminho -Base (Get-LocalAppData) -Parte 'Programs/chatgpt/ChatGPT.exe'),
            (Join-Caminho -Base (Get-LocalAppData) -Parte 'Programs/ChatGPT/ChatGPT.exe'),
            (Join-Caminho -Base (Get-LocalAppData) -Parte 'ChatGPT/ChatGPT.exe'))) {
            if (Test-Path -LiteralPath $p) { return $p }
        }
        return $null
    }
    foreach ($b in @('chatgpt', 'codex')) {
        $c = Get-Command $b -ErrorAction SilentlyContinue
        if ($c) { return $c.Source }
    }
    return $null
}

function Test-CodexInstalado {
    $c = Get-Command codex -ErrorAction SilentlyContinue
    return [bool]$c
}

function Test-OpenCodeInstalado {
    $c = Get-Command opencode -ErrorAction SilentlyContinue
    return [bool]$c
}

# UUID v4 em minúsculas. A versão bash usava uuidgen (macOS) ou
# /proc/sys/kernel/random/uuid (Linux). Aqui não há dependência de SO.
function New-UuidLower {
    return ([guid]::NewGuid().ToString()).ToLowerInvariant()
}

# Nome do processo por app, para encerrar com elegância antes de reler a config.
# A config 3P é lida uma vez no lançamento: sem reiniciar, nada muda.
function Restart-ClaudeDesktop {
    if ($env:CLI_SEM_REINICIAR -eq '1') { return }
    if (-not (Test-ClaudeDesktopInstalado)) { return }
    if (Test-MacOS) {
        $proc = Get-Process -Name 'Claude' -ErrorAction SilentlyContinue
        if (-not $proc) { return }
        & osascript -e 'tell application "Claude" to quit' 2>$null | Out-Null
        Start-Sleep -Seconds 2
        $proc = Get-Process -Name 'Claude' -ErrorAction SilentlyContinue
        if ($proc) { $proc | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500 }
        Start-Process -FilePath 'Claude' -ErrorAction SilentlyContinue
        return
    }
    if (Test-Windows) {
        $proc = Get-Process -Name 'Claude' -ErrorAction SilentlyContinue
        if (-not $proc) { return }
        $proc | Stop-Process -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $proc = Get-Process -Name 'Claude' -ErrorAction SilentlyContinue
        if ($proc) { $proc | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500 }
        # MSIX não abre por caminho: o protocolo do app é o jeito confiável.
        try {
            Start-Process 'shell:AppsFolder\Claude' -ErrorAction Stop
        } catch {
            $exe = Join-Caminho -Base (Get-LocalAppData) -Parte 'AnthropicClaude\Claude.exe'
            if (Test-Path -LiteralPath $exe) { Start-Process $exe -ErrorAction SilentlyContinue }
        }
        return
    }
    # Linux: não reinicia sozinho; o usuário abre quando quiser.
    return
}

function Restart-ChatGPT {
    if ($env:CLI_SEM_REINICIAR -eq '1') { return }
    $app = Get-ChatGPTApp
    if (-not $app) { return }
    if (Test-MacOS) {
        $proc = Get-Process -Name 'ChatGPT' -ErrorAction SilentlyContinue
        if (-not $proc) { return }
        & osascript -e 'tell application "ChatGPT" to quit' 2>$null | Out-Null
        Start-Sleep -Seconds 2
        Get-Process -Name 'ChatGPT' -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        Start-Process -FilePath $app -ErrorAction SilentlyContinue
        return
    }
    if (Test-Windows) {
        $proc = Get-Process -Name 'ChatGPT' -ErrorAction SilentlyContinue
        if (-not $proc) { return }
        $proc | Stop-Process -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Get-Process -Name 'ChatGPT' -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        try { Start-Process 'shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0' -ErrorAction Stop }
        catch { Start-Process $app -ErrorAction SilentlyContinue }
        return
    }
    return
}

# ── Arquivos de ambiente do shell ───────────────────────────────────────────
# No macOS e Linux, o Claude Code lê as variáveis do .zshrc/.bashrc. No Windows
# não existe esse arquivo: variável de ambiente de usuário é o equivalente, e
# é o que um processo novo herda.
function Set-EnvVariavelUsuario {
    param([Parameter(Mandatory)][string]$Nome, [Parameter(Mandatory)][AllowEmptyString()][string]$Valor)
    if (Test-Windows) {
        [Environment]::SetEnvironmentVariable($Nome, $Valor, 'User')
        return $true
    }
    return $false
}

function Remove-EnvVariavelUsuario {
    param([Parameter(Mandatory)][string]$Nome)
    if (Test-Windows) {
        [Environment]::SetEnvironmentVariable($Nome, $null, 'User')
        return $true
    }
    return $false
}

function Get-EnvVariavelUsuario {
    param([Parameter(Mandatory)][string]$Nome)
    if (Test-Windows) {
        return [Environment]::GetEnvironmentVariable($Nome, 'User')
    }
    return $null
}

# Arquivos de shell que valem tratar, por plataforma. No Windows devolve vazio:
# o caminho lá é variável de ambiente, não arquivo.
function Get-RcFiles {
    if (Test-Windows) { return @() }
    $home_ = Get-HomeRaiz
    $out = @()
    foreach ($f in @('.zshrc', '.bashrc')) {
        $p = Join-Caminho -Base $home_ -Parte $f
        if (Test-Path -LiteralPath $p) { $out += $p }
    }
    if ($out.Count -eq 0) {
        $z = Join-Caminho -Base $home_ -Parte '.zshrc'
        if (Test-MacOS) { $out += $z }
    }
    return $out
}

# Aviso honesto quando a plataforma muda o significado de alguma etapa.
function Get-AvisoPlataforma {
    $avisos = @()
    if (Test-Windows) {
        $avisos += 'No Windows as variáveis do Claude Code vão para o ambiente do usuário (não há .zshrc).'
        $avisos += 'A configuração do Claude Desktop é lida uma vez no lançamento: o app precisa ser reaberto.'
    }
    return $avisos
}