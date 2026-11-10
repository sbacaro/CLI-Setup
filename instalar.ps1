#Requires -Version 7.0
<#
.SYNOPSIS
    CLI Setup — configurador de terminal (Windows / macOS / Linux).

.DESCRIPTION
    Liga Claude Code, Claude Desktop, OpenCode, Codex (CLI) e ChatGPT Desktop
    ao gateway, lendo os modelos do SEU plano em vez de usar lista fixa.

    Desfazer: rode de novo e marque o que está "configurado".

.EXAMPLE
    # com a chave (pula a tela da chave)
    irm https://raw.githubusercontent.com/sbacaro/CLI-Setup/main/instalar.ps1 | iex

    # ou, com a chave em variável:
    $env:CLI_KEY = "ck_..."; ./instalar.ps1

.EXAMPLE
    # desfazer tudo
    ./instalar.ps1 -Desfazer
#>
[CmdletBinding()]
param(
    [string]$Chave = '',
    [switch]$Desfazer,
    [switch]$SemReiniciar,
    # Aplica sem perguntar nada. Serve para teste automatizado e para provisionar
    # uma máquina de uma vez (CI, imagem, script de onboarding).
    #   -NaoInterativo -Ferramentas "claude-code,opencode"
    [switch]$NaoInterativo,
    [string]$Ferramentas = '',
    [ValidateSet('minimo', 'padrao', 'completo')][string]$Egress = 'padrao',
    # No modo não interativo, "configurar" mesmo que a ferramenta já esteja
    # configurada. Sem isso, -Ferramentas numa máquina já configurada DESFAZ
    # em vez de reaplicar, que é o oposto do esperado.
    [switch]$Forcar
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:Versao = '3.0'
$script:Base = if ($env:CLI_BASE) { $env:CLI_BASE } else { 'https://api.kodeo.com.br' }
$script:MarcaIni = '# >>> kodeo >>>'
$script:MarcaFim = '# <<< kodeo <<<'
$script:Falhas = 0
$script:Baixou = $false

if ($SemReiniciar) { $env:CLI_SEM_REINICIAR = '1' }

# ── bibliotecas ────────────────────────────────────────────────────────────
# O comando do painel é "irm ... | iex", que não tem as pastas ao lado. Então:
# usa a pasta local quando existe (desenvolvimento) e, quando não existe, baixa
# do mesmo repositório para uma pasta temporária.
$script:Raiz = ''
$candidatos = @($PSScriptRoot, (Get-Location).Path)
foreach ($c in $candidatos) {
    if ($c -and (Test-Path -LiteralPath ([IO.Path]::Combine($c, 'ps', 'Json.ps1')))) {
        $script:Raiz = $c
        break
    }
}
if (-not $script:Raiz) {
    # Join-Caminho ainda não existe (vem de Plataforma.ps1), então monta com
    # o separador nativo.
    $tmpNome = "cli-setup-" + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $tmp = [IO.Path]::Combine([IO.Path]::GetTempPath(), $tmpNome)
    New-Item -ItemType Directory -Force -Path ([IO.Path]::Combine($tmp, 'ps')) | Out-Null
    $script:Raiz = $tmp
    $script:Baixou = $true
}

$script:ArquivosLib = @('Plataforma', 'Json', 'Catalogo', 'Geradores', 'Desktop', 'Ui')
foreach ($f in $script:ArquivosLib) {
    $p = [IO.Path]::Combine($script:Raiz, 'ps', "$f.ps1")
    if (-not (Test-Path -LiteralPath $p)) {
        throw "nao encontrei $p — baixe o repositorio inteiro ou verifique a internet"
    }
}

# Plataforma primeiro: os outros módulos usam os caminhos dela.
. ([IO.Path]::Combine($script:Raiz, 'ps', 'Plataforma.ps1'))
. ([IO.Path]::Combine($script:Raiz, 'ps', 'Json.ps1'))
. ([IO.Path]::Combine($script:Raiz, 'ps', 'Catalogo.ps1'))
. ([IO.Path]::Combine($script:Raiz, 'ps', 'Geradores.ps1'))
. ([IO.Path]::Combine($script:Raiz, 'ps', 'Desktop.ps1'))
. ([IO.Path]::Combine($script:Raiz, 'ps', 'Ui.ps1'))

if (-not $NaoInterativo) { Assert-Terminal }
Measure-Terminal
if ($NaoInterativo) { $script:Larg = 76 }

# ── caminhos, resolvidos uma vez ───────────────────────────────────────────
$script:CfgClaudeCode = Get-ClaudeCodeSettings
$script:CfgOpenCode   = Get-OpenCodeConfig
$script:ChaveOpenCode = Get-OpenCodeKeyFile
$script:CfgCodex      = Get-CodexConfig
$script:DirCodex      = Get-CodexDir
$script:CatCodex      = Join-Caminho -Base $script:DirCodex -Parte 'cli-setup-models.json'
$script:ModeloCodex   = Join-Caminho -Base $script:DirCodex -Parte '.cli-setup-modelo'
$script:BkCodex       = Join-Caminho -Base (Get-HomeRaiz) -Parte '.config/cli-setup/codex-config.toml.anterior'
$script:DirClaude3p   = Get-Claude3pDir
$script:LibClaude3p   = Get-Claude3pConfigLibrary

# ══ 1/5  CHAVE ═════════════════════════════════════════════════════════════
# O estado vive em $script:ChaveAtiva, não em $script:Chave: atribuir a
# $script:Chave criaria uma variável nova que sombreia o parâmetro homônimo.
$script:ChaveAtiva = ''
if ($Chave) { $script:ChaveAtiva = $Chave }
elseif ($env:CLI_KEY) { $script:ChaveAtiva = $env:CLI_KEY }
elseif ($env:KODEO_KEY) { $script:ChaveAtiva = $env:KODEO_KEY }

$script:ChaveDoComando = [bool]$script:ChaveAtiva

function Test-FormatoChave {
    param([string]$K)
    return ($K -match '^ck_......')
}

function Test-ChaveApi {
    param([Parameter(Mandatory)][string]$K)
    return (Get-HttpStatus -Uri "$script:Base/v1/me" -ApiKey $K) -eq '200'
}

function Show-TelaChave {
    Show-Tela -Dir "1/$($script:Total)  Chave" -Etapa 1
    Write-Linha "$($script:B)$($script:W)Passo 1 de $($script:Total) — a chave.$($script:R)"
    Write-Linha ''
    Write-Linha 'O configurador precisa da sua chave para ver quais modelos o seu plano tem.'
    Write-Linha 'Ela fica só nos arquivos de configuração das ferramentas que você marcar.'
    Write-Linha "$($script:G)Onde achar: painel da Kodeo -> API -> chaves (começa com ck_).$($script:R)"
    Write-Linha ''
    Write-Rodape -Dicas @('enter:continuar', 'backspace:apagar', 'ctrl+c:sair')

    $buf = ''
    Write-CursorOn
    while ($true) {
        Clear-Linha
        Write-Host "$($script:Espaco)  $($script:ACC)$([char]0x276F)$($script:R) " -NoNewline
        Write-Host ('•' * $buf.Length) -NoNewline
        try { $k = Read-Tecla } catch { Write-Cancela }
        switch ($k) {
            'enter' {
                if (-not (Test-FormatoChave $buf)) {
                    Write-Host ''
                    Write-Host "$($script:Espaco)  $($script:ERR)$([char]0x2717)$($script:R) A chave começa com ck_. Confira e tente de novo."
                    Write-Host "$($script:E)[1A" -NoNewline
                    continue
                }
                $st = Get-HttpStatus -Uri "$script:Base/v1/me" -ApiKey $buf
                if ($st -eq '200') { break }
                Write-Host ''
                if ($st -eq '401' -or $st -eq '403') {
                    Write-Host "$($script:Espaco)  $($script:ERR)$([char]0x2717)$($script:R) A API recusou essa chave. Confira no painel e cole de novo."
                } else {
                    Write-Host "$($script:Espaco)  $($script:WARN)!$($script:R) Não consegui falar com $($script:Base -replace '^https://','') ($st). Verifique a internet."
                }
                Write-Host "$($script:E)[1A" -NoNewline
            }
            'bs' { if ($buf.Length -gt 0) { $buf = $buf.Substring(0, $buf.Length - 1) } }
            'space' { $buf += ' ' }
            'eof' { Write-Cancela }
            '' { }
            default { if ($k.Length -eq 1) { $buf += $k } }
        }
    }
    Write-CursorOff
    $script:ChaveAtiva = $buf
    Write-Host ''
    Clear-Linha
    Write-Host "$($script:Espaco)  $($script:OK)$([char]0x2713)$($script:R) Chave válida"
    Start-Sleep -Milliseconds 400
}

function Show-TelaChaveDoComando {
    Show-Tela -Dir "1/$($script:Total)  Chave" -Etapa 1
    Write-Linha "$($script:B)$($script:W)Passo 1 de $($script:Total) — a chave.$($script:R)"
    Write-Linha ''
    Write-Linha 'Chave recebida.'
    Write-Linha ''
    $i = 0
    Clear-Linha
    Write-Host "$($script:Espaco)  $($script:ACC)$($script:Spin[0])$($script:R) Verificando a chave" -NoNewline
    $st = Get-HttpStatus -Uri "$script:Base/v1/me" -ApiKey $script:ChaveAtiva
    Clear-Linha
    if ($st -eq '200') {
        Write-Host "$($script:Espaco)  $($script:OK)$([char]0x2713)$($script:R) Chave válida"
        Start-Sleep -Milliseconds 500
        return $true
    }
    if ($st -eq '401' -or $st -eq '403') {
        Write-Host "$($script:Espaco)  $($script:ERR)$([char]0x2717)$($script:R) A API recusou a chave. Pegue o comando de novo no painel."
    } else {
        Write-Host "$($script:Espaco)  $($script:WARN)!$($script:R) Não consegui falar com $($script:Base -replace '^https://','') ($st). Verifique a internet."
    }
    Write-Rodape -Dicas @('enter:sair')
    $null = Wait-Continuar -PermiteVoltar $false
    exit 1
}

if ($NaoInterativo) {
    # Sem tela: valida e segue. Mensagem curta, uma linha, própria de log.
    if (-not $script:ChaveAtiva) { Write-Host 'falta a chave (-Chave ou CLI_KEY)'; exit 2 }
    if (-not (Test-FormatoChave $script:ChaveAtiva)) { Write-Host 'a chave começa com ck_'; exit 2 }
    $st = Get-HttpStatus -Uri "$script:Base/v1/me" -ApiKey $script:ChaveAtiva
    if ($st -ne '200') { Write-Host "a API recusou a chave ($st)"; exit 2 }
} elseif (-not $script:ChaveDoComando) {
    Show-TelaChave
} else {
    if (-not (Show-TelaChaveDoComando)) { exit 1 }
}

# ══ 2/5  FERRAMENTAS ═══════════════════════════════════════════════════════
# Cinco serviços, não quatro: o Codex CLI aparece em "where codex"; o ChatGPT
# Desktop é um app da Store no Windows e um .app no macOS. A detecção é
# separada, mas o alvo de gravação é o mesmo ~/.codex/config.toml.
$script:Nomes    = @('Claude Code', 'Claude Desktop', 'OpenCode', 'Codex', 'ChatGPT Desktop')
$script:Ids      = @('claude-code', 'claude-app', 'opencode', 'codex', 'chatgpt')
$script:Conf     = @($false, $false, $false, $false, $false)
$script:Sel      = @($false, $false, $false, $false, $false)
$script:Inst     = @($false, $false, $false, $false, $false)

function Find-TextoEmArquivo {
    param([string]$Caminho, [string]$Padrao)
    if (-not (Test-Path -LiteralPath $Caminho)) { return $false }
    try {
        $t = [IO.File]::ReadAllText($Caminho)
        # (?m) para o "^" casar em qualquer linha: sem isso o padrão só casaria
        # no começo do arquivo inteiro, e as marcas ficam no meio.
        return ($t -match "(?m)$Padrao")
    } catch { return $false }
}

function Get-Deteccao {
    # Claude Code: settings.json é a fonte principal.
    if (Find-TextoEmArquivo $script:CfgClaudeCode 'api\.kodeo\.com\.br') {
        $script:Conf[0] = $true
    } elseif (Test-Windows) {
        # No Windows não há .zshrc: o vestígio é a variável de ambiente.
        if ((Get-EnvVariavelUsuario 'ANTHROPIC_BASE_URL') -match 'kodeo') { $script:Conf[0] = $true }
    } else {
        foreach ($f in (Get-RcFiles)) {
            if ((Find-TextoEmArquivo $f '^# >>> kodeo >>>') -and (Find-TextoEmArquivo $f 'ANTHROPIC_BASE_URL')) {
                $script:Conf[0] = $true; break
            }
        }
    }
    if (Get-Command claude -ErrorAction SilentlyContinue) { $script:Inst[0] = $true }

    # Claude Desktop: configLibrary é mais confiável que o .json principal.
    $meta = Join-Caminho -Base $script:LibClaude3p -Parte '_meta.json'
    if ((Find-TextoEmArquivo $meta '"name"\s*:\s*"Kodeo"')) { $script:Conf[1] = $true }
    if (Test-ClaudeDesktopInstalado) { $script:Inst[1] = $true }

    # OpenCode
    if (Find-TextoEmArquivo $script:CfgOpenCode '"kodeo"') { $script:Conf[2] = $true }
    if (Test-OpenCodeInstalado) { $script:Inst[2] = $true }

    # Codex (CLI)
    if (Find-TextoEmArquivo $script:CfgCodex 'model_providers\.kodeo') { $script:Conf[3] = $true }
    if (Test-CodexInstalado) { $script:Inst[3] = $true }

    # ChatGPT Desktop compartilha o config.toml, então o estado de configuração
    # é o mesmo. O que muda é a instalação.
    $script:Conf[4] = $script:Conf[3]
    if (Get-ChatGPTApp) { $script:Inst[4] = $true }

    # Se nada está configurado, marca todos para seleção.
    $algum = $false
    for ($i = 0; $i -lt 5; $i++) { if ($script:Conf[$i]) { $algum = $true } }
    if (-not $algum) { for ($i = 0; $i -lt 5; $i++) { $script:Sel[$i] = $true } }
}

function Show-TelaFerramentas {
    while ($true) {
        Show-Tela -Dir "2/$($script:Total)  Ferramentas" -Etapa 2
        Write-Linha "$($script:B)$($script:W)Passo 2 de $($script:Total) — o que configurar.$($script:R)"
        Write-Linha ''
        Write-Linha 'O que já está configurado pode ser desconfigurado.'
        Write-Linha "$($script:G)Codex (CLI) e ChatGPT Desktop leem o mesmo config.toml: marcar um$($script:R)"
        Write-Linha "$($script:G)aplica nos dois. A detecção de instalação é separada.$($script:R)"
        if (Test-Windows) {
            Write-Linha "$($script:G)Windows: Claude Desktop, ChatGPT e Codex são apps/CLIs nativos.$($script:R)"
        }
        Write-Linha ''

        $itens = @()
        for ($i = 0; $i -lt 5; $i++) {
            $estado = 'nao configurado'
            $acao = 'configurar'
            if ($script:Conf[$i]) { $estado = 'configurado'; $acao = 'desconfigurar' }
            if (-not $script:Inst[$i] -and -not $script:Conf[$i]) { $estado = 'nao encontrado' }
            $itens += ,([ordered]@{ Nome = $script:Nomes[$i]; Estado = $estado; Acao = $acao })
        }

        $dicas = @('↑↓:mover', 'espaço:marcar', 'enter:continuar', 'ctrl+c:sair')
        if (-not $script:ChaveDoComando) { $dicas = @('↑↓:mover', 'espaço:marcar', 'enter:continuar', '←:voltar', 'ctrl+c:sair') }

        $r = Show-Menu -Itens $itens -Marcado $script:Sel -Rodape $dicas -PermiteVoltar (-not $script:ChaveDoComando)
        if ($r.Indice -lt 0) {
            if ($script:ChaveDoComando) { continue }
            return 'voltar'
        }
        $novo = @()
        foreach ($m in $r.Marcado) { $novo += [bool]$m }
        $script:Sel = $novo
        $algum = $false
        foreach ($s in $script:Sel) { if ($s) { $algum = $true } }
        if ($algum) { return 'seguir' }
    }
}

# ══ 3/5  MODELOS ═══════════════════════════════════════════════════════════
$script:OpusId = ''; $script:SonnetId = ''; $script:HaikuId = ''
$script:PadraoId = ''; $script:CatFalhou = $false

function Read-Catalogo {
    Clear-Linha
    Write-Host "$($script:Espaco)  $($script:ACC)$($script:Spin[0])$($script:R) Lendo os modelos do seu plano" -NoNewline
    $ok = Initialize-Catalogo -ApiKey $script:ChaveAtiva
    Clear-Linha
    if (-not $ok) { $script:CatFalhou = $true; return $false }
    $null = Initialize-Plano -ApiKey $script:ChaveAtiva
    if ((Get-ModeloContagem) -le 0) { $script:CatFalhou = $true; return $false }
    $script:OpusId = Get-MelhorTier 'opus'
    $script:SonnetId = Get-MelhorTier 'sonnet'
    $script:HaikuId = Get-MelhorTier 'haiku'
    $script:PadraoId = Get-PadraoGeral
    return $true
}

function Show-TelaModelos {
    while ($true) {
        Show-Tela -Dir "3/$($script:Total)  Modelos" -Etapa 3
        Write-Linha "$($script:B)$($script:W)Passo 3 de $($script:Total) — os modelos do seu plano.$($script:R)"
        Write-Linha ''
        if (-not (Read-Catalogo)) {
            Write-Linha "$($script:ERR)$([char]0x2717)$($script:R) Não consegui ler o catálogo da API."
            Write-Linha "  A chave é válida, mas $($script:Base -replace '^https://','')/v1/models não respondeu."
            Write-Linha ''
            Write-Rodape -Dicas @('enter:tentar', '←:voltar', 'ctrl+c:sair')
            $k = Wait-Continuar
            if ($k -eq 'left') { return 'voltar' }
            continue
        }
        $res = Get-ResumoPlano
        Write-Linha "$($script:OK)$([char]0x2713)$($script:R) $($res.Total) modelos no seu plano"
        Write-Linha ''
        Write-Linha "$($script:B)$($script:W)O que cada app recebe:$($script:R)"
        Write-Linha "  $($script:G)Claude Code / Desktop$($script:R)  $($res.Anthropic) modelos Anthropic"
        Write-Linha "  $($script:G)ChatGPT / Codex$($script:R)         $($res.OpenAI) modelos OpenAI"
        Write-Linha "  $($script:G)OpenCode$($script:R)                $($res.Total) modelos (todos)"
        Write-Linha ''
        Write-Linha "$($script:G)Padrão para começar:$($script:R) $($script:W)$($script:PadraoId)$($script:R)"
        Write-Linha ''
        Write-Linha "$($script:G)Modelos de planos superiores ficam de fora: o catálogo da API lista tudo,$($script:R)"
        Write-Linha "$($script:G)mas só os do seu plano respondem. Um deles devolveria 403.$($script:R)"
        Write-Linha ''
        $atalhos = "$($script:G)Atalhos no Claude Desktop:$($script:R)"
        foreach ($m in @($script:OpusId, $script:SonnetId, $script:HaikuId)) {
            if ($m) { $atalhos += "  $($script:W)$m$($script:R)" }
        }
        Write-Linha $atalhos
        Write-Linha ''
        Write-Rodape -Dicas @('enter:continuar', '←:voltar', 'ctrl+c:sair')
        $k = Wait-Continuar
        if ($k -eq 'left') { return 'voltar' }
        if ($k -eq 'enter') { return 'seguir' }
    }
}

# ══ 4/5  DESKTOP ═══════════════════════════════════════════════════════════
# O que o app perde ao sair da assinatura Anthropic. Cada item restaura uma
# camada com um caminho que funciona sem infraestrutura da Anthropic.
$script:BuscaProvedor = if ($env:CLI_BUSCA_PROVEDOR) { $env:CLI_BUSCA_PROVEDOR } else { '' }
$script:BuscaChave    = if ($env:CLI_BUSCA_CHAVE) { $env:CLI_BUSCA_CHAVE } else { '' }
$script:GithubClientId = if ($env:CLI_GITHUB_CLIENT_ID) { $env:CLI_GITHUB_CLIENT_ID } else { '' }
$script:EgressMode    = 'padrao'
$script:RemotosSel    = @()
$script:UsarMcpLocal  = $true
$script:DirMcpLocal   = @()
$script:IncluirSkills = $true
$script:IncluirCode   = $true

function Show-TelaDesktop {
    while ($true) {
        Show-Tela -Dir "4/$($script:Total)  Desktop" -Etapa 4
        Write-Linha "$($script:B)$($script:W)Passo 4 de $($script:Total) — o que o app perde fora da assinatura.$($script:R)"
        Write-Linha ''
        Write-Linha 'Com um gateway, o Claude Desktop deixa de receber do Console da Anthropic:'
        Write-Linha 'conectores, skills e plugins. Esta etapa devolve as três camadas.'
        Write-Linha ''

        if (-not $script:Sel[1]) {
            Write-Linha "$($script:G)Claude Desktop não está marcado — pulando.$($script:R)"
            Write-Linha ''
            Write-Rodape -Dicas @('enter:continuar', '←:voltar', 'ctrl+c:sair')
            $k = Wait-Continuar
            if ($k -eq 'left') { return 'voltar' }
            return 'seguir'
        }

        $itens = @(
            [ordered]@{
                Nome = 'Continuar'
                Estado = 'configurado'
                Acao = 'aplicar estas camadas'
            }
            [ordered]@{
                Nome = 'Skills e plugins'
                Estado = $(if ($script:IncluirSkills -and $script:IncluirCode) { 'configurado' } else { 'nao configurado' })
                Acao = 'marketplaces oficiais'
            }
            [ordered]@{
                Nome = 'MCP local (npx)'
                Estado = $(if ($script:UsarMcpLocal) { 'configurado' } else { 'nao configurado' })
                Acao = 'filesystem, memory, thinking'
            }
            [ordered]@{
                Nome = 'Conectores remotos'
                Estado = $(if ($script:RemotosSel.Count -gt 0) { 'configurado' } else { 'nao configurado' })
                Acao = 'Linear, Notion, Sentry...'
            }
            [ordered]@{
                Nome = 'Egress da sandbox'
                Estado = 'configurado'
                Acao = "nivel: $($script:EgressMode)"
            }
        )
        Write-Linha "$($script:B)$($script:W)Camadas:$($script:R)"
        Write-Rodape -Dicas @('↑↓:mover', 'enter:escolher', '←:voltar', 'ctrl+c:sair')
        $r = Show-Menu -Itens $itens -Multi $false -PermiteVoltar $true
        if ($r.Indice -lt 0) { return 'voltar' }
        if ($r.Indice -eq 0) { return 'seguir' }

        switch ($r.Indice) {
            1 {
                $opts = @(
                    [ordered]@{ Nome = 'anthropics/skills'; Estado = $(if ($script:IncluirSkills) { 'configurado' } else { 'nao configurado' }); Acao = 'skills oficiais' }
                    [ordered]@{ Nome = 'anthropics/claude-code'; Estado = $(if ($script:IncluirCode) { 'configurado' } else { 'nao configurado' }); Acao = 'plugins do Claude Code' }
                )
                $rr = Show-Menu -Itens $opts -Marcado @($script:IncluirSkills, $script:IncluirCode) -Rodape @('espaço:marcar', 'enter:voltar')
                if ($rr.Indice -ge 0) {
                    $script:IncluirSkills = [bool]$rr.Marcado[0]
                    $script:IncluirCode   = [bool]$rr.Marcado[1]
                }
            }
            2 {
                $opt = @([ordered]@{ Nome = 'Instalar servidores locais via npx'; Estado = $(if ($script:UsarMcpLocal) { 'configurado' } else { 'nao configurado' }); Acao = 'baixa no cache do npm' })
                $rr = Show-Menu -Itens $opt -Marcado @($script:UsarMcpLocal) -Rodape @('espaço:marcar', 'enter:voltar')
                if ($rr.Indice -ge 0) { $script:UsarMcpLocal = [bool]$rr.Marcado[0] }
            }
            3 {
                $opts = @()
                $marcado = @()
                foreach ($rem in (Get-RemotosLista)) {
                    $opts += ,([ordered]@{ Nome = $rem.nome; Estado = $(if ($script:RemotosSel -contains $rem.chave) { 'configurado' } else { 'nao configurado' }); Acao = $rem.transporte })
                    $marcado += ($script:RemotosSel -contains $rem.chave)
                }
                $rr = Show-Menu -Itens $opts -Marcado $marcado -Rodape @('espaço:marcar', 'enter:voltar')
                if ($rr.Indice -ge 0) {
                    $novo = @()
                    $ids = @((Get-RemotosLista) | ForEach-Object { $_.chave })
                    for ($i = 0; $i -lt $ids.Count; $i++) {
                        if ($rr.Marcado[$i]) { $novo += $ids[$i] }
                    }
                    $script:RemotosSel = $novo
                }
            }
            4 {
                $opts = @(
                    [ordered]@{ Nome = 'minimo';   Estado = $(if ($script:EgressMode -eq 'minimo')   { 'configurado' } else { 'nao configurado' }); Acao = '2 hosts' }
                    [ordered]@{ Nome = 'padrao';   Estado = $(if ($script:EgressMode -eq 'padrao')   { 'configurado' } else { 'nao configurado' }); Acao = '11 hosts' }
                    [ordered]@{ Nome = 'completo'; Estado = $(if ($script:EgressMode -eq 'completo') { 'configurado' } else { 'nao configurado' }); Acao = '17 hosts' }
                )
                $rr = Show-Menu -Itens $opts -Multi $false -Rodape @('enter:escolher', '←:voltar')
                if ($rr.Indice -ge 0) {
                    $script:EgressMode = @('minimo', 'padrao', 'completo')[$rr.Indice]
                }
            }
        }
    }
}

# ══ 5/5  APLICAR ═══════════════════════════════════════════════════════════

function Write-Passo {
    param([string]$Texto, [scriptblock]$Acao)
    $ok = $false
    try {
        $ok = [bool](& $Acao)
    } catch {
        $ok = $false
        $msg = $_.Exception.Message
    }
    Clear-Linha
    if ($ok) {
        Write-Host "$($script:Espaco)  $($script:OK)$([char]0x2713)$($script:R) $Texto"
    } else {
        $detalhe = if ($msg) { " $($script:G)($msg)$($script:R)" } else { '' }
        Write-Host "$($script:Espaco)  $($script:ERR)$([char]0xD7)$($script:R) $Texto$detalhe"
        $script:Falhas++
    }
    return $ok
}

# ── Claude Code ────────────────────────────────────────────────────────────
function Set-BlocoShell {
    param([string]$Caminho)
    $ini = $script:MarcaIni
    $fim = $script:MarcaFim
    $envMapa = Get-ClaudeCodeEnv -Base $script:Base -Chave $script:ChaveAtiva `
        -Opus $script:OpusId -Sonnet $script:SonnetId -Haiku $script:HaikuId
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine($ini)
    foreach ($kv in $envMapa.GetEnumerator()) {
        [void]$sb.AppendLine("export $($kv.Key)=`"$($kv.Value)`"")
    }
    [void]$sb.AppendLine("export KODEO_API_KEY=`"$($script:ChaveAtiva)`"")
    [void]$sb.AppendLine($fim)

    $corpo = ''
    if (Test-Path -LiteralPath $Caminho) {
        $t = [IO.File]::ReadAllText($Caminho)
        $corpo = Remove-BlocoMarcado -Texto $t -Ini $ini -Fim $fim
    }
    Write-FileAtomic -Path $Caminho -Content ($corpo.TrimEnd() + "`n" + $sb.ToString())
    return $true
}

function Install-ClaudeCode {
    $envJson = [ordered]@{ env = (Get-ClaudeCodeEnv -Base $script:Base -Chave $script:ChaveAtiva -Opus $script:OpusId -Sonnet $script:SonnetId -Haiku $script:HaikuId) }
    $null = Write-Passo 'Variáveis e modelos do plano em settings.json' {
        Update-JsonFile -Path $script:CfgClaudeCode -Operation merge -Value $envJson
    }

    if (Test-Windows) {
        # Não há .zshrc no Windows: variável de ambiente de usuário é o
        # equivalente, e é o que um processo novo herda.
        $null = Write-Passo 'Variáveis no ambiente do usuário (Windows)' {
            $mapa = Get-ClaudeCodeEnv -Base $script:Base -Chave $script:ChaveAtiva -Opus $script:OpusId -Sonnet $script:SonnetId -Haiku $script:HaikuId
            $mapa['KODEO_API_KEY'] = $script:ChaveAtiva
            foreach ($kv in $mapa.GetEnumerator()) {
                $null = Set-EnvVariavelUsuario -Nome $kv.Key -Valor $kv.Value
            }
            $env:ANTHROPIC_BASE_URL = $script:Base
            $env:ANTHROPIC_AUTH_TOKEN = $script:ChaveAtiva
            $true
        }
    } else {
        foreach ($f in (Get-RcFiles)) {
            $alvo = $f
            $null = Write-Passo "Atalhos de modelo em $($alvo -replace [regex]::Escape((Get-HomeRaiz)), '~')" {
                Set-BlocoShell -Caminho $alvo
            }
        }
    }

    $null = Write-Passo 'Teste de conexão' {
        (Get-HttpStatus -Uri "$script:Base/v1/models" -ApiKey $script:ChaveAtiva) -eq '200'
    }
}

function Uninstall-ClaudeCode {
    if (Test-Path -LiteralPath $script:CfgClaudeCode) {
        $null = Write-Passo 'Tirar as variáveis do settings.json' {
            Update-JsonFile -Path $script:CfgClaudeCode -Operation del -Value @('env')
        }
    }
    if (Test-Windows) {
        $null = Write-Passo 'Tirar as variáveis do ambiente do usuário' {
            foreach ($n in @('ANTHROPIC_BASE_URL', 'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_DEFAULT_OPUS_MODEL',
                             'ANTHROPIC_DEFAULT_SONNET_MODEL', 'ANTHROPIC_DEFAULT_HAIKU_MODEL', 'KODEO_API_KEY')) {
                $null = Remove-EnvVariavelUsuario -Nome $n
            }
            Remove-Item Env:ANTHROPIC_BASE_URL -ErrorAction SilentlyContinue
            Remove-Item Env:ANTHROPIC_AUTH_TOKEN -ErrorAction SilentlyContinue
            $true
        }
    } else {
        foreach ($f in (Get-RcFiles)) {
            if (-not (Find-TextoEmArquivo $f '^# >>> kodeo >>>')) { continue }
            # Se o Codex continua configurado, o bloco fica só com a chave dele.
            if (Find-TextoEmArquivo $script:CfgCodex 'model_providers\.kodeo') {
                $alvo = $f
                $null = Write-Passo "Manter só a KODEO_API_KEY em $($alvo -replace [regex]::Escape((Get-HomeRaiz)), '~')" {
                    Set-BlocoShellSoChave -Caminho $alvo
                }
            } else {
                $alvo = $f
                $null = Write-Passo "Remover o bloco de $($alvo -replace [regex]::Escape((Get-HomeRaiz)), '~')" {
                    Remove-BlocoDoArquivo -Caminho $alvo
                }
            }
        }
    }
}

function Set-BlocoShellSoChave {
    param([string]$Caminho)
    $t = [IO.File]::ReadAllText($Caminho)
    $corpo = Remove-BlocoMarcado -Texto $t -Ini $script:MarcaIni -Fim $script:MarcaFim
    $bloco = "$($script:MarcaIni)`nexport KODEO_API_KEY=`"$($script:ChaveAtiva)`"`n$($script:MarcaFim)`n"
    Write-FileAtomic -Path $Caminho -Content ($corpo.TrimEnd() + "`n" + $bloco)
    return $true
}

function Remove-BlocoDoArquivo {
    param([string]$Caminho)
    if (-not (Test-Path -LiteralPath $Caminho)) { return $true }
    $t = [IO.File]::ReadAllText($Caminho)
    $corpo = Remove-BlocoMarcado -Texto $t -Ini $script:MarcaIni -Fim $script:MarcaFim
    if ([string]::IsNullOrWhiteSpace($corpo)) { Remove-Item -LiteralPath $Caminho -Force }
    else { Write-FileAtomic -Path $Caminho -Content ($corpo.TrimEnd() + "`n") }
    return $true
}

# ── Claude Desktop ─────────────────────────────────────────────────────────
function New-ConfigClaudeDesktop {
    $mk = @()
    if ($script:IncluirSkills -or $script:IncluirCode) {
        $mk = @(Get-Marketplaces -IncluirSkills ([int]$script:IncluirSkills) -IncluirCode ([int]$script:IncluirCode))
    }
    $eg = @(Get-EgressHosts -Nivel $script:EgressMode)
    $ml = @()
    if ($script:UsarMcpLocal) { $ml = @(Get-McpLocal -Diretorios ($script:DirMcpLocal -join ',')) }
    $mr = @(Get-McpRemoto -Selecao ($script:RemotosSel -join ','))
    return (New-ClaudeDesktopConfig -Base $script:Base -Chave $script:ChaveAtiva -Padrao $script:PadraoId `
        -Marketplaces $mk -Egress $eg -McpLocal $ml -McpRemoto $mr `
        -BuscaProvedor $script:BuscaProvedor -BuscaChave $script:BuscaChave -GithubClientId $script:GithubClientId)
}

function Write-ConfigClaudeDesktop {
    if (-not (Test-CatalogoLido)) {
        $script:ErroPasso = 'catálogo vazio: rode a etapa de modelos antes'
        return $false
    }
    if (-not (Test-Path -LiteralPath $script:LibClaude3p)) {
        New-Item -ItemType Directory -Force -Path $script:LibClaude3p | Out-Null
    }
    $id = New-UuidLower
    $cfg = New-ConfigClaudeDesktop
    $json = ConvertTo-JsonText $cfg
    if ($json -notmatch 'inferenceModels') { $script:ErroPasso = 'config sem modelos'; return $false }

    # Remove um config nosso anterior (só o nosso: o do usuário fica).
    $meta = Join-Caminho -Base $script:LibClaude3p -Parte '_meta.json'
    if (Test-Path -LiteralPath $meta) {
        if (Find-TextoEmArquivo $meta '"name"\s*:\s*"Kodeo"') {
            try {
                $mj = Read-JsonMap $meta
                $ant = "$($mj['appliedId'])"
                if ($ant) { Remove-Item -LiteralPath (Join-Caminho -Base $script:LibClaude3p -Parte "$ant.json") -Force -ErrorAction SilentlyContinue }
            } catch {}
            Remove-Item -LiteralPath $meta -Force -ErrorAction SilentlyContinue
        }
    }

    Write-FileAtomic -Path (Join-Caminho -Base $script:LibClaude3p -Parte "$id.json") -Content $json
    $metaObj = [ordered]@{ appliedId = $id; entries = @([ordered]@{ id = $id; name = 'Kodeo' }) }
    Write-JsonFile -Path $meta -Value $metaObj
    return $true
}

function Set-DeploymentMode {
    param([string]$Modo)
    $arq = Join-Caminho -Base $script:DirClaude3p -Parte 'claude_desktop_config.json'
    return (Update-JsonFile -Path $arq -Operation merge -Value ([ordered]@{ deploymentMode = $Modo }))
}

function Set-DevTools {
    $arq = Join-Caminho -Base $script:DirClaude3p -Parte 'developer_settings.json'
    return (Update-JsonFile -Path $arq -Operation merge -Value ([ordered]@{ allowDevTools = $true }))
}

function Install-ClaudeDesktop {
    $null = Write-Passo 'Configuração (modelos e camadas) em Claude-3p/configLibrary' {
        Write-ConfigClaudeDesktop
    }
    $null = Write-Passo 'deploymentMode = 3p' { Set-DeploymentMode '3p' }
    $null = Write-Passo 'Modo desenvolvedor (allowDevTools)' { Set-DevTools }
    if (-not $env:CLI_SEM_REINICIAR -eq '1') {
        $null = Write-Passo 'Reiniciar o Claude (se estiver aberto)' {
            Restart-ClaudeDesktop
            $true
        }
    }
}

function Uninstall-ClaudeDesktop {
    $lib = $script:LibClaude3p
    $null = Write-Passo 'Remover a configuração do Claude Desktop' {
        $meta = Join-Caminho -Base $lib -Parte '_meta.json'
        if (-not (Test-Path -LiteralPath $meta)) { return $true }
        if (-not (Find-TextoEmArquivo $meta '"name"\s*:\s*"Kodeo"')) { return $true }
        try {
            $mj = Read-JsonMap $meta
            $id = "$($mj['appliedId'])"
            if ($id) { Remove-Item -LiteralPath (Join-Caminho -Base $lib -Parte "$id.json") -Force -ErrorAction SilentlyContinue }
        } catch {}
        Remove-Item -LiteralPath $meta -Force -ErrorAction SilentlyContinue
        $true
    }
    $arq = Join-Caminho -Base $script:DirClaude3p -Parte 'claude_desktop_config.json'
    if (Test-Path -LiteralPath $arq) {
        $null = Write-Passo 'deploymentMode = 1p' { Set-DeploymentMode '1p' }
    }
    if (-not $env:CLI_SEM_REINICIAR -eq '1') {
        $null = Write-Passo 'Reiniciar o Claude (se estiver aberto)' {
            Restart-ClaudeDesktop
            $true
        }
    }
}

# ── OpenCode ───────────────────────────────────────────────────────────────
function Install-OpenCode {
    $null = Write-Passo 'Provedor e os modelos do plano em opencode.json' {
        $modelos = New-OpenCodeModelos
        $prov = New-OpenCodeProvider -Base $script:Base -Modelos $modelos
        # Guarda o modelo anterior para o desfazer devolver.
        $ant = ''
        if (Test-Path -LiteralPath $script:CfgOpenCode) {
            $m = Get-JsonPath $script:CfgOpenCode 'model'
            if ($m -and "$m" -notmatch '^kodeo/') { $ant = "$m" }
        }
        if ($ant) {
            Write-FileAtomic -Path "$($script:CfgOpenCode).modelo-anterior" -Content $ant
        }
        if (-not (Update-JsonFile -Path $script:CfgOpenCode -Operation merge -Value $prov)) { return $false }
        $null = Update-JsonFile -Path $script:CfgOpenCode -Operation merge -Value ([ordered]@{ model = "kodeo/$($script:PadraoId)" })
        $true
    }
    $null = Write-Passo 'Integração para a chave aparecer em /connect' {
        Update-JsonFile -Path $script:CfgOpenCode -Operation merge -Value (New-OpenCodeIntegracao)
    }
    $null = Write-Passo 'Chave disponível para o OpenCode' {
        $dir = Split-Path -Parent $script:ChaveOpenCode
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        Write-FileAtomic -Path $script:ChaveOpenCode -Content $script:ChaveAtiva
        # Restringe a leitura ao dono (no Windows, o ACL padrão do perfil já faz).
        if (-not (Test-Windows)) {
            try { & chmod 600 $script:ChaveOpenCode 2>$null } catch {}
        }
        # O runtime do OpenCode aceita a chave pelo ambiente do serviço.
        $oc = Get-Command opencode -ErrorAction SilentlyContinue
        if ($oc) { try { $null = & $oc.Source service set env KODEO_API_KEY $script:ChaveAtiva 2>$null } catch {} }
        $true
    }
    if (Test-Windows) {
        $null = Write-Passo 'KODEO_API_KEY no ambiente do usuário (Windows)' {
            $null = Set-EnvVariavelUsuario -Nome 'KODEO_API_KEY' -Valor $script:ChaveAtiva
            $env:KODEO_API_KEY = $script:ChaveAtiva
            $true
        }
    } else {
        foreach ($f in (Get-RcFiles)) {
            $alvo = $f
            $null = Write-Passo "KODEO_API_KEY em $($alvo -replace [regex]::Escape((Get-HomeRaiz)), '~') (o provedor lê do ambiente)" {
                Set-BlocoShellSoChave -Caminho $alvo
            }
        }
    }
    $null = Write-Passo "Modelo padrão: kodeo/$($script:PadraoId)" { $true }
}

function Uninstall-OpenCode {
    $null = Write-Passo 'Tirar o provedor do opencode.json' {
        if (-not (Test-Path -LiteralPath $script:CfgOpenCode)) { return $true }
        $ant = ''
        $antArq = "$($script:CfgOpenCode).modelo-anterior"
        if (Test-Path -LiteralPath $antArq) { $ant = [IO.File]::ReadAllText($antArq) }
        $atual = Get-JsonPath $script:CfgOpenCode 'model'
        # "integrations" também é nosso: sem o provedor ela fica órfã.
        if (-not (Update-JsonFile -Path $script:CfgOpenCode -Operation del -Value @('providers', 'integrations'))) { return $false }
        if ("$atual" -match '^kodeo/') {
            if ($ant) {
                $null = Update-JsonFile -Path $script:CfgOpenCode -Operation merge -Value ([ordered]@{ model = $ant })
            } else {
                $null = Update-JsonFile -Path $script:CfgOpenCode -Operation del -Value @('model')
            }
        }
        # Se o arquivo ficou vazio, remove.
        if (Test-Path -LiteralPath $script:CfgOpenCode) {
            $t = [IO.File]::ReadAllText($script:CfgOpenCode) -replace '[\s\{\}]', ''
            if ([string]::IsNullOrEmpty($t)) { Remove-Item -LiteralPath $script:CfgOpenCode -Force }
        }
        $true
    }
    foreach ($p in @($script:ChaveOpenCode, "$($script:CfgOpenCode).modelo-anterior")) {
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
    }
    $oc = Get-Command opencode -ErrorAction SilentlyContinue
    if ($oc) { try { $null = & $oc.Source service unset env KODEO_API_KEY 2>$null } catch {} }

    # Se nenhuma outra ferramenta precisa da chave, tira do ambiente.
    $precisa = (Find-TextoEmArquivo $script:CfgClaudeCode 'api\.kodeo\.com\.br') -or
               (Find-TextoEmArquivo $script:CfgCodex 'model_providers\.kodeo')
    if (-not $precisa) {
        if (Test-Windows) {
            $null = Write-Passo 'Tirar KODEO_API_KEY do ambiente do usuário' {
                $null = Remove-EnvVariavelUsuario -Nome 'KODEO_API_KEY'
                Remove-Item Env:KODEO_API_KEY -ErrorAction SilentlyContinue
                $true
            }
        } else {
            foreach ($f in (Get-RcFiles)) {
                if (-not (Find-TextoEmArquivo $f '^# >>> kodeo >>>')) { continue }
                if (Find-TextoEmArquivo $f 'ANTHROPIC_BASE_URL') { continue }
                $alvo = $f
                $null = Write-Passo "Remover KODEO_API_KEY de $($alvo -replace [regex]::Escape((Get-HomeRaiz)), '~')" {
                    Remove-BlocoDoArquivo -Caminho $alvo
                }
            }
        }
    }
}

# ── Codex / ChatGPT Desktop ────────────────────────────────────────────────
function Write-CatalogoCodex {
    # O catálogo do Codex vem de /v1/codex/modelos, não do /v1/models: só ele
    # traz os 36 campos que o app valida.
    if (-not (Initialize-CatalogoCodex -ApiKey $script:ChaveAtiva)) {
        $script:ErroPasso = 'não consegui ler /v1/codex/modelos'
        return $false
    }
    $dir = $script:DirCodex
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    # O Codex/ChatGPT só aceita OpenAI. O padrão global é Anthropic, então usar
    # ele aqui gravava um modelo inválido no catálogo deles.
    $modelo = Get-PadraoOpenAI
    if (-not $modelo) { $script:ErroPasso = 'o plano não tem nenhum modelo OpenAI'; return $false }

    # O modelo vai por arquivo: é o que atravessa entre passos sem depender de
    # escopo de variável (na versão bash este era o bug).
    Write-FileAtomic -Path $script:ModeloCodex -Content $modelo

    $cat = New-CodexCatalogo -ModeloPadrao $modelo
    Write-JsonFile -Path $script:CatCodex -Value $cat

    if (-not (Test-Path -LiteralPath $script:CatCodex)) { return $false }
    return $true
}

function Write-ConfigCodex {
    $dir = $script:DirCodex
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    # Backup do arquivo original, uma vez só, para o desfazer restaurar.
    if (-not (Test-Path -LiteralPath $script:BkCodex)) {
        $bkDir = Split-Path -Parent $script:BkCodex
        if (-not (Test-Path -LiteralPath $bkDir)) { New-Item -ItemType Directory -Force -Path $bkDir | Out-Null }
        if (Test-Path -LiteralPath $script:CfgCodex) { Copy-Item -LiteralPath $script:CfgCodex -Destination $script:BkCodex -Force }
    }

    $modelo = ''
    if (Test-Path -LiteralPath $script:ModeloCodex) { $modelo = ([IO.File]::ReadAllText($script:ModeloCodex)).Trim() }
    if (-not $modelo) { $modelo = Get-PadraoOpenAI }
    if (-not $modelo) { $script:ErroPasso = 'não há modelo OpenAI no plano'; return $false }

    $corpo = ''
    if (Test-Path -LiteralPath $script:CfgCodex) { $corpo = [IO.File]::ReadAllText($script:CfgCodex) }
    # Uma passada só: Remove-BlocoMarcado já descarta as marcas antigas do
    # provedor como comentário e delimita a tabela por "[". Uma segunda passada
    # por marcas antigas engoliria o arquivo inteiro, porque a marca de fim
    # ficava no fim do arquivo, depois de plugins e mcp_servers.
    $corpo = Remove-BlocoMarcado -Texto $corpo -Ini $script:MarcaIni -Fim $script:MarcaFim -TabelaProvedor

    # Separa cabeçalho (chaves soltas) do resto (tabelas). As chaves que nós
    # controlamos saem do cabeçalho para não duplicar.
    $linhas = $corpo -split "`r?`n"
    $cabeca = @(); $cauda = @(); $emTabela = $false
    foreach ($l in $linhas) {
        if (-not $emTabela -and $l -match '^\s*\[') { $emTabela = $true }
        if ($emTabela) { $cauda += $l }
        else {
            if ($l -match '^\s*(model|model_provider|model_catalog_json)\s*=') { continue }
            $cabeca += $l
        }
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine((Get-CodexBlocoTopo -Modelo $modelo -CatalogoCaminho $script:CatCodex).TrimEnd())
    $cab = ($cabeca -join "`n").Trim()
    if ($cab) { [void]$sb.AppendLine($cab) }
    $cau = ($cauda -join "`n").Trim()
    if ($cau) { [void]$sb.AppendLine($cau) }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine((Get-CodexBlocoProvider -Base $script:Base).TrimEnd())

    Write-FileAtomic -Path $script:CfgCodex -Content $sb.ToString()
    return $true
}

function Install-Codex {
    $null = Write-Passo 'Lista de modelos do plano em cli-setup-models.json' { Write-CatalogoCodex }
    $null = Write-Passo 'Provedor e modelo OpenAI do plano em config.toml' { Write-ConfigCodex }

    if (Test-Windows) {
        $null = Write-Passo 'KODEO_API_KEY no ambiente do usuário (Windows)' {
            $null = Set-EnvVariavelUsuario -Nome 'KODEO_API_KEY' -Valor $script:ChaveAtiva
            $env:KODEO_API_KEY = $script:ChaveAtiva
            $true
        }
    } else {
        foreach ($f in (Get-RcFiles)) {
            $alvo = $f
            $null = Write-Passo "KODEO_API_KEY em $($alvo -replace [regex]::Escape((Get-HomeRaiz)), '~')" {
                Set-BlocoShellSoChave -Caminho $alvo
            }
        }
    }

    $null = Write-Passo 'Teste de conexão (responses)' {
        $corpo = ConvertTo-Json -Compress -InputObject ([ordered]@{
            model = Get-PadraoOpenAI; input = 'Responda só: ok'; max_output_tokens = 20; store = $false
        })
        $r = Invoke-Api -Uri "$script:Base/v1/responses" -ApiKey $script:ChaveAtiva -Metodo 'POST' -Corpo $corpo -TimeoutSec 60
        $null -ne $r -and [int]$r.StatusCode -eq 200
    }

    if (Get-ChatGPTApp) {
        $null = Write-Passo 'Reiniciar o ChatGPT Desktop (se estiver aberto)' {
            Restart-ChatGPT
            $true
        }
    }
}

function Uninstall-Codex {
    $null = Write-Passo 'Remover o provedor do config.toml' {
        if (Test-Path -LiteralPath $script:BkCodex) {
            Copy-Item -LiteralPath $script:BkCodex -Destination $script:CfgCodex -Force
            Remove-Item -LiteralPath $script:BkCodex -Force -ErrorAction SilentlyContinue
            return $true
        }
        if (-not (Test-Path -LiteralPath $script:CfgCodex)) { return $true }
        $t = [IO.File]::ReadAllText($script:CfgCodex)
        if ($t -notmatch '^# >>> kodeo') { return $true }
        $resto = Remove-BlocoMarcado -Texto $t -Ini $script:MarcaIni -Fim $script:MarcaFim -TabelaProvedor
        if ([string]::IsNullOrWhiteSpace($resto)) { Remove-Item -LiteralPath $script:CfgCodex -Force }
        else { Write-FileAtomic -Path $script:CfgCodex -Content ($resto.TrimEnd() + "`n") }
        $true
    }
    foreach ($p in @($script:CatCodex, $script:ModeloCodex)) {
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
    }
    # Se o bloco do shell ficou só com a chave do Codex, ele sai agora: era o
    # único consumidor dela. Se o Claude Code ainda usa o bloco (tem
    # ANTHROPIC_BASE_URL), fica para o desfazer dele.
    if (Test-Windows) {
        if (-not (Find-TextoEmArquivo $script:CfgClaudeCode 'api\.kodeo\.com\.br')) {
            $null = Write-Passo 'Tirar KODEO_API_KEY do ambiente do usuário' {
                $null = Remove-EnvVariavelUsuario -Nome 'KODEO_API_KEY'
                Remove-Item Env:KODEO_API_KEY -ErrorAction SilentlyContinue
                $true
            }
        }
    } else {
        foreach ($f in (Get-RcFiles)) {
            if (-not (Find-TextoEmArquivo $f '^# >>> kodeo >>>')) { continue }
            if (Find-TextoEmArquivo $f 'ANTHROPIC_BASE_URL') { continue }
            $alvo = $f
            $null = Write-Passo "Remover KODEO_API_KEY de $($alvo -replace [regex]::Escape((Get-HomeRaiz)), '~')" {
                Remove-BlocoDoArquivo -Caminho $alvo
            }
        }
    }
    $null = Write-Passo 'Catálogo do Codex removido' { $true }
    if (Get-ChatGPTApp) {
        $null = Write-Passo 'Reiniciar o ChatGPT Desktop (se estiver aberto)' {
            Restart-ChatGPT
            $true
        }
    }
}

# ── resumo ─────────────────────────────────────────────────────────────────
function Show-Resumo {
    param([array]$Feitas, [array]$Removidas)
    Show-Tela -Dir "5/$($script:Total)  Pronto" -Etapa 5
    $m = if ($script:ChaveAtiva.Length -gt 12) { $script:ChaveAtiva.Substring(0, 9) + '…' + $script:ChaveAtiva.Substring($script:ChaveAtiva.Length - 4) } else { $script:ChaveAtiva }
    Write-Linha "$($script:B)$($script:W)Pronto.$($script:R)"
    Write-Linha ''
    if ($Feitas.Count -gt 0) {
        Write-Linha "$($script:OK)Configurado:$($script:R) $($Feitas -join ', ')"
    }
    if ($Removidas.Count -gt 0) {
        Write-Linha "$($script:G)Desconfigurado:$($script:R) $($Removidas -join ', ')"
    }
    Write-Linha ''
    Write-Linha "Chave: $m"
    Write-Linha "Gateway: $($script:Base)"
    Write-Linha "Plano: $($script:PadraoId)"
    Write-Linha ''
    foreach ($a in (Get-AvisoPlataforma)) { Write-Linha "$($script:G)$a$($script:R)" }
    if ($script:Falhas -gt 0) {
        Write-Linha ''
        Write-Linha "$($script:ERR)$($script:Falhas) passo(s) falharam.$($script:R) Veja acima o que não foi aplicado."
    }
    Write-Linha ''
    if (Test-Windows) {
        Write-Linha "$($script:G)Para abrir o Claude Desktop em modo 3P: Develop -> Configure third-party inference$($script:R)"
    }
    Write-Linha "$($script:G)Para desfazer: rode de novo e marque o que está configurado.$($script:R)"
    Write-Linha ''
    Write-Rodape -Dicas @('enter:sair')
    $null = Wait-Continuar -PermiteVoltar $false
}

function Show-Aplicar {
    Show-Tela -Dir "5/$($script:Total)  Aplicar" -Etapa 5
    Write-Rodape -Dicas @('aguarde:aplicando')
    $feitas = @(); $removidas = @()
    # Codex e ChatGPT escrevem no mesmo arquivo: marcar os dois aplica uma vez.
    $feitoCx = $false
    for ($i = 0; $i -lt $script:Nomes.Count; $i++) {
        if (-not $script:Sel[$i]) { continue }
        if ($script:Conf[$i]) {
            Write-Host "$($script:Espaco)  $($script:B)$($script:W)$($script:Nomes[$i])$($script:R) $($script:G)desconfigurar$($script:R)"
            switch ($script:Ids[$i]) {
                'claude-code' { Uninstall-ClaudeCode }
                'claude-app'  { Uninstall-ClaudeDesktop }
                'opencode'    { Uninstall-OpenCode }
                { $_ -in @('codex', 'chatgpt') } {
                    if (-not $feitoCx) { Uninstall-Codex; $feitoCx = $true }
                }
            }
            $removidas += $script:Nomes[$i]
        } else {
            Write-Host "$($script:Espaco)  $($script:B)$($script:W)$($script:Nomes[$i])$($script:R) $($script:G)configurar$($script:R)"
            switch ($script:Ids[$i]) {
                'claude-code' { Install-ClaudeCode }
                'claude-app'  { Install-ClaudeDesktop }
                'opencode'    { Install-OpenCode }
                { $_ -in @('codex', 'chatgpt') } {
                    if (-not $feitoCx) { Install-Codex; $feitoCx = $true }
                }
            }
            $feitas += $script:Nomes[$i]
        }
        Write-Host ''
    }
    Show-Resumo -Feitas $feitas -Removidas $removidas
}

# ══ principal ══════════════════════════════════════════════════════════════
# O fluxo fica numa função com returns explícitos. Um `switch` solto no topo
# do script emite cada valor para o pipeline, e o texto das telas se misturava
# com o valor de retorno — foi o que fez "seguir" aparecer colado em cada linha.
function Invoke-Fluxo {
    if ($NaoInterativo) {
        # Sem telas: a seleção vem do parâmetro. As variáveis de estilo ficam
        # vazias para a saída ser texto limpo (log de CI, saída de teste).
        $script:E = ''; $script:R = ''; $script:B = ''; $script:W = ''
        $script:G = ''; $script:OK = ''; $script:ERR = ''; $script:WARN = ''; $script:ACC = ''
        $script:EgressMode = $Egress
        # Não interativo significa "aplique isto": zerar o estado de
        # configuração faz Show-Aplicar configurar em vez de desfazer.
        if (-not $Desfazer -and ($Forcar -or $Ferramentas)) {
            for ($i = 0; $i -lt 5; $i++) { $script:Conf[$i] = $false }
        }
        # -Desfazer manda o contrário: só age no que está configurado.
        if ($Desfazer) {
            for ($i = 0; $i -lt 5; $i++) { $script:Conf[$i] = $true }
        }
        $pedidas = @($Ferramentas -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        for ($i = 0; $i -lt 5; $i++) { $script:Sel[$i] = $false }
        for ($i = 0; $i -lt 5; $i++) {
            if ($pedidas.Count -eq 0 -or $pedidas -contains $script:Ids[$i]) {
                $script:Sel[$i] = $true
            }
        }
        if (-not (Read-Catalogo)) {
            Write-Host "nao consegui ler o catalogo do plano"
            $script:Falhas++
            return
        }
        Show-Aplicar
        return
    }

    if ($Desfazer) {
        for ($i = 0; $i -lt 5; $i++) { $script:Sel[$i] = $script:Conf[$i] }
        $null = Read-Catalogo
        Show-Aplicar
        return
    }

    # if/elseif, não switch: no PowerShell, `continue` dentro de um switch
    # continua o switch, não o while em volta — o fluxo caía fora e saía.
    $passo = 'ferramentas'
    while ($true) {
        if ($passo -eq 'ferramentas') {
            $r = Show-TelaFerramentas
            if ($r -eq 'voltar') {
                Show-TelaChave
                $null = Show-TelaFerramentas
            }
            $passo = 'modelos'
        } elseif ($passo -eq 'modelos') {
            $r = Show-TelaModelos
            if ($r -eq 'voltar') { $passo = 'ferramentas'; continue }
            $passo = 'desktop'
        } elseif ($passo -eq 'desktop') {
            $r = Show-TelaDesktop
            if ($r -eq 'voltar') { $passo = 'modelos'; continue }
            $passo = 'aplicar'
        } else {
            $null = Read-Catalogo
            Show-Aplicar
            return
        }
    }
}

try {
    if (-not $NaoInterativo) { Show-Abertura -Versao $script:Versao }
    Get-Deteccao
    Invoke-Fluxo
} catch [System.OperationCanceledException] {
    Write-Cancela
} finally {
    Write-CursorOn
    Write-Host "$($script:R)"
    if ($script:Baixou -and $script:Raiz -and (Test-Path -LiteralPath $script:Raiz)) {
        Remove-Item -LiteralPath $script:Raiz -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($script:Falhas -gt 0) { exit 1 }
exit 0