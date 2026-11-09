# ps/Desktop.ps1 — configuração do Claude Desktop 3P para ficar equivalente ao
# app com assinatura Anthropic.
#
# O problema: ao apontar o app para um gateway, ele sai do modo Anthropic e
# perde conectores, skills e plugins. Tudo que vinha do Console da Anthropic
# deixa de existir. A config abaixo devolve essas camadas por caminhos que
# funcionam sem infraestrutura da Anthropic, sem inventar host nenhum:
#
#   1. Conectores embutidos no app (server: websearch | github). Rodam como
#      processo local na máquina do usuário. Nada passa por host da Anthropic.
#   2. Skills e plugins pelos marketplaces oficiais no GitHub, Apache 2.0 —
#      os mesmos repositórios que alimentam o Claude real.
#   3. Plugins de organização pelo diretório org-plugins (só informado: exige
#      administrador para escrever, então o configurador não escreve lá).
#
# Cada valor foi conferido na documentação oficial
# (claude.com/docs/third-party/claude-desktop) ou é repositório público real.

Set-StrictMode -Version Latest

# ── Marketplaces oficiais ──────────────────────────────────────────────────
# Ambos são repositórios públicos, sem autenticação, com
# .claude-plugin/marketplace.json. "ref" vazio rastreia o branch padrão: sempre
# a versão mais recente, sem valor fixo que envelhece. A doc exige SHA de 40
# caracteres apenas quando installationPreference é auto_install/required —
# aqui é "available", então branch é aceito e preferível.
$script:SkillsRepo = if ($env:KODEO_SKILLS_REPO) { $env:KODEO_SKILLS_REPO } else { 'anthropics/skills' }
$script:CodeRepo   = if ($env:KODEO_CODE_PLUGINS_REPO) { $env:KODEO_CODE_PLUGINS_REPO } else { 'anthropics/claude-code' }

function Get-Marketplaces {
    param([int]$IncluirSkills = 1, [int]$IncluirCode = 1)
    $out = @()
    if ($IncluirSkills -eq 1) {
        $out += ,([ordered]@{
            source                 = 'github'
            repo                   = $script:SkillsRepo
            expectedName           = 'anthropic-agent-skills'
            credentialKind         = 'anonymous'
            installationPreference = 'available'
        })
    }
    if ($IncluirCode -eq 1) {
        $out += ,([ordered]@{
            source                 = 'github'
            repo                   = $script:CodeRepo
            expectedName           = 'claude-code-plugins'
            credentialKind         = 'anonymous'
            installationPreference = 'available'
        })
    }
    return $out
}

# ── Egress allowlist ───────────────────────────────────────────────────────
# Hosts que a sandbox do Cowork pode alcançar. Sem isso, Web Fetch e o shell
# dentro da sandbox não saem. Inclui os hosts do marketplace (github) e os
# provedores de busca (o conector websearch roda fora da sandbox, mas o Web
# Fetch dos resultados precisa passar).
function Get-EgressHosts {
    param([ValidateSet('minimo', 'padrao', 'completo')][string]$Nivel = 'padrao')
    switch ($Nivel) {
        'minimo' {
            return @('github.com', 'api.github.com')
        }
        'completo' {
            return @(
                'github.com', 'api.github.com', 'raw.githubusercontent.com',
                'objects.githubusercontent.com', 'codeload.github.com',
                'gitlab.com', 'bitbucket.org',
                'pypi.org', 'files.pythonhosted.org',
                'registry.npmjs.org', 'npmjs.org',
                'deb.debian.org', 'archive.ubuntu.com', 'security.ubuntu.com',
                'api.search.brave.com', 'api.tavily.com', 'api.exa.ai'
            )
        }
        default {
            return @(
                'github.com', 'api.github.com', 'raw.githubusercontent.com',
                'objects.githubusercontent.com',
                'pypi.org', 'files.pythonhosted.org',
                'registry.npmjs.org', 'npmjs.org',
                'api.search.brave.com', 'api.tavily.com', 'api.exa.ai'
            )
        }
    }
}

# ── Conectores remotos oficiais (vendor-hosted, OAuth) ─────────────────────
# Cada URL foi verificada: responde 401 (existe, pede OAuth) e serve
# /.well-known/oauth-protected-resource ou
# /.well-known/oauth-authorization-server, que é o que o app exige para
# registrar o cliente e abrir o navegador.
#
# São os substitutos reais dos conectores "Made by Anthropic", que só existem
# na infraestrutura da Anthropic. Estes rodam no host do fornecedor e ficam
# acessíveis em 3P. Nenhum precisa de chave: o usuário clica Connect e o app
# faz o fluxo OAuth no navegador.
$script:DesktopRemotos = @(
    [ordered]@{ chave = 'linear';    nome = 'Linear';    url = 'https://mcp.linear.app/mcp';      transporte = 'http' },
    [ordered]@{ chave = 'notion';    nome = 'Notion';    url = 'https://mcp.notion.com/mcp';      transporte = 'http' },
    [ordered]@{ chave = 'sentry';    nome = 'Sentry';    url = 'https://mcp.sentry.dev/mcp';      transporte = 'http' },
    [ordered]@{ chave = 'atlassian'; nome = 'Atlassian'; url = 'https://mcp.atlassian.com/v1/mcp'; transporte = 'http' },
    [ordered]@{ chave = 'stripe';    nome = 'Stripe';    url = 'https://mcp.stripe.com';          transporte = 'http' },
    [ordered]@{ chave = 'asana';     nome = 'Asana';     url = 'https://mcp.asana.com/sse';       transporte = 'sse' }
)

function Get-RemotosLista { return $script:DesktopRemotos }

# Seleção vira array JSON. Chaves separadas por vírgula.
function Get-McpRemoto {
    param([string]$Selecao = '')
    $sel = @($Selecao -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($sel.Count -eq 0) { return @() }
    $out = @()
    foreach ($r in $script:DesktopRemotos) {
        if ($sel -contains $r.chave) {
            $out += ,([ordered]@{
                name      = $r.nome
                transport = $r.transporte
                url       = $r.url
                oauth     = $true
            })
        }
    }
    # Array de verdade sempre: com um item só, o PowerShell devolveria o
    # objeto direto e quem chama não conseguiria indexar (era o caso de
    # "asana"). Com zero itens, `,$out` produziria um array-de-array.
    if ($out.Count -eq 0) { return @() }
    return ,$out
}

# ── MCP local via npx ──────────────────────────────────────────────────────
# A doc exige que "command" seja caminho ABSOLUTO do executável. npx resolve
# isso, mas o pacote só está disponível depois do primeiro download. Por isso
# pré-aquecemos: npx -y <pacote> --version baixa para o cache do npm, e aí o
# app encontra o pacote já em disco quando for conectar.
#
# Só incluímos o servidor cujo pacote baixou de verdade. Sem isso o app
# mostraria erro de conexão em vez de funcionar.
#
# No Windows o npx é npx.cmd e o cache fica em %LOCALAPPDATA%\npm-cache\_npx
# (ou %APPDATA%\npm-cache). Os dois são cobertos abaixo.

function Get-NpmCacheDir {
    if ($env:npm_config_cache) { return $env:npm_config_cache }
    if (Test-Windows) {
        $p = Join-Caminho -Base (Get-LocalAppData) -Parte 'npm-cache'
        if (Test-Path -LiteralPath $p) { return $p }
        return (Join-Caminho -Base (Get-AppData) -Parte 'npm-cache')
    }
    return (Join-Caminho -Base (Get-HomeRaiz) -Parte '.npm')
}

function Get-NpxComando {
    $c = Get-Command npx -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    # No Windows o shim costuma ser npx.cmd, que Get-Command acha, mas em
    # alguns PATHs só o .ps1 aparece. Onde há .cmd, é ele que executa.
    foreach ($ext in @('cmd', 'ps1', 'exe')) {
        $c = Get-Command "npx.$ext" -ErrorAction SilentlyContinue
        if ($c) { return $c.Source }
    }
    return $null
}

# Aquece o pacote no cache do npm. Devolve $true se o cache tem o pacote.
function Invoke-NpxAquecer {
    param([Parameter(Mandatory)][string]$Pacote)
    $npx = Get-NpxComando
    if (-not $npx) { return $false }
    # Já instalado globalmente? Então não precisa baixar.
    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if ($npm) {
        $null = & $npm.Source ls -g --depth=0 $Pacote 2>$null
        if ($LASTEXITCODE -eq 0) { return $true }
    }
    # --help sai não-zero em vários pacotes; o que interessa é o download.
    try {
        $null = & $npx -y $Pacote --help 2>$null
    } catch {}
    $npxDir = Join-Caminho -Base (Get-NpmCacheDir) -Parte '_npx'
    return (Test-Path -LiteralPath $npxDir)
}

# Caminho absoluto do binário dentro do cache do npm.
# No Windows o executável real é o .cmd dentro de node_modules/.bin.
function Get-NpxBinario {
    param(
        [Parameter(Mandatory)][string]$Pacote,
        [Parameter(Mandatory)][string]$Comando
    )
    $npxDir = Join-Caminho -Base (Get-NpmCacheDir) -Parte '_npx'
    if (Test-Path -LiteralPath $npxDir) {
        $exts = if (Test-Windows) { @('.cmd', '.exe', '.ps1', '') } else { @('') }
        foreach ($d in (Get-ChildItem -LiteralPath $npxDir -Directory -ErrorAction SilentlyContinue)) {
            foreach ($ext in $exts) {
                $p = Join-Caminho -Base $d.FullName -Parte "node_modules/.bin/$Comando$ext"
                if (Test-Path -LiteralPath $p) { return $p }
            }
        }
    }
    # Global
    $c = Get-Command $Comando -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}

# Servidores stdio locais reais. Só entram os que resolvem para um binário
# absoluto existente — declarar um comando que não existe faz o app mostrar
# erro de conexão em vez de funcionar.
function Get-McpLocal {
    param([string]$Diretorios = '')

    $dirs = @($Diretorios -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($dirs.Count -eq 0) { return @() }

    $out = @()

    if (Invoke-NpxAquecer -Pacote '@modelcontextprotocol/server-filesystem') {
        $bin = Get-NpxBinario -Pacote '@modelcontextprotocol/server-filesystem' -Comando 'mcp-server-filesystem'
        if ($bin) {
            $args_ = @($dirs)
            $out += ,([ordered]@{
                name       = 'Filesystem'
                transport  = 'stdio'
                command    = $bin
                args       = $args_
                toolPolicy = [ordered]@{ write_file = 'ask'; delete_file = 'ask' }
            })
        }
    }

    if (Invoke-NpxAquecer -Pacote '@modelcontextprotocol/server-memory') {
        $bin = Get-NpxBinario -Pacote '@modelcontextprotocol/server-memory' -Comando 'mcp-server-memory'
        if ($bin) {
            $out += ,([ordered]@{
                name      = 'Memory'
                transport = 'stdio'
                command   = $bin
                args      = @()
            })
        }
    }

    if (Invoke-NpxAquecer -Pacote '@modelcontextprotocol/server-sequential-thinking') {
        $bin = Get-NpxBinario -Pacote '@modelcontextprotocol/server-sequential-thinking' -Comando 'mcp-server-sequential-thinking'
        if ($bin) {
            $out += ,([ordered]@{
                name      = 'Sequential Thinking'
                transport = 'stdio'
                command   = $bin
                args      = @()
            })
        }
    }

    return $out
}