# ps/Catalogo.ps1 — lê o catálogo de modelos do plano na API e responde
# perguntas sobre ele.
#
# A ideia central veio da versão bash e continua: nada de lista fixa. A API sabe
# quais modelos o plano tem; o configurador pergunta e cada ferramenta recebe a
# lista que ela espera.
#
# Diferença da versão bash: lá era preciso node ou python3 para ler o JSON
# porque o shell não tem isso. Aqui ConvertFrom-Json é nativo, então a camada
# inteira roda só com o PowerShell.

Set-StrictMode -Version Latest

$script:CatalogoJson = $null       # objeto cru de /v1/models
$script:CatalogoLido = $false
$script:PlanoIds = @()             # ids liberados pelo plano (/v1/me → modelos)
$script:PlanoCarregado = $false

function Get-CatalogoJson { return $script:CatalogoJson }
function Set-CatalogoJson {
    param($Value)
    $script:CatalogoJson = $Value
    $script:CatalogoLido = $true
}
function Test-CatalogoLido { return $script:CatalogoLido }
function Get-PlanoIds { return $script:PlanoIds }
function Set-PlanoIds {
    param([string[]]$Ids)
    $script:PlanoIds = @($Ids)
    $script:PlanoCarregado = $true
}
function Test-PlanoCarregado { return $script:PlanoCarregado }

# ── família e tier, pelo id ─────────────────────────────────────────────────
# A ordem importa: "claude-opus-5-kodeo" contém claude e opus; "kodeo-opus-5"
# não contém claude mas é Opus.
function Get-Familia {
    param([string]$Id)
    $i = $Id.ToLowerInvariant()
    if ($i -match 'claude|opus|fable|sonnet|haiku|mythos') { return 'anthropic' }
    if ($i -match 'gpt|codex')                              { return 'openai' }
    if ($i -match 'grok')                                   { return 'xai' }
    if ($i -match 'glm')                                    { return 'zhipu' }
    if ($i -match 'deepseek')                               { return 'deepseek' }
    if ($i -match 'minimax')                                { return 'minimax' }
    return 'outro'
}

function Get-Tier {
    param([string]$Id)
    $i = $Id.ToLowerInvariant()
    foreach ($t in @('opus', 'sonnet', 'haiku', 'fable', 'mythos')) {
        if ($i -match $t) { return $t }
    }
    return ''
}

# Versão embutida no nome: "opus-5.5" → 5.5, "gpt-6.1-sol" → 6.1.
# Usada para preferir o mais novo quando há várias versões do mesmo tier.
function Get-VersaoModelo {
    param([string]$Id)
    $m = [regex]::Matches([string]$Id, '\d+(?:\.\d+)?')
    if ($m.Count -eq 0) { return 0.0 }
    $max = 0.0
    foreach ($x in $m) {
        $v = [double]::Parse($x.Value, [Globalization.CultureInfo]::InvariantCulture)
        if ($v -gt $max) { $max = $v }
    }
    return $max
}

# ── catálogo bruto ──────────────────────────────────────────────────────────
# GET /v1/models devolve o catálogo INTEIRO, incluindo modelos de planos
# superiores. Para saber o que o usuário pode usar, é o /v1/me que responde.
function Get-CatalogoModelos {
    if ($null -eq $script:CatalogoJson) { return @() }
    $d = $script:CatalogoJson
    if ($d.PSObject.Properties['data'] -and $d.data) { return @($d.data) }
    if ($d.PSObject.Properties['models'] -and $d.models) { return @($d.models) }
    return @()
}

function Get-ModeloId {
    param($Modelo)
    if ($Modelo.PSObject.Properties['id'] -and $Modelo.id) { return [string]$Modelo.id }
    if ($Modelo.PSObject.Properties['slug'] -and $Modelo.slug) { return [string]$Modelo.slug }
    return ''
}

function Get-ModeloNome {
    param($Modelo)
    $id = Get-ModeloId $Modelo
    foreach ($c in @('display_name', 'name')) {
        if ($Modelo.PSObject.Properties[$c] -and $Modelo.$c) { return [string]$Modelo.$c }
    }
    return $id
}

function Get-ModeloContexto {
    param($Modelo)
    foreach ($c in @('context_length', 'context_window', 'max_input_tokens')) {
        if ($Modelo.PSObject.Properties[$c] -and $Modelo.$c) { return [int64]$Modelo.$c }
    }
    return 0
}

function Get-ModeloSaida {
    param($Modelo)
    if ($Modelo.PSObject.Properties['max_tokens'] -and $Modelo.max_tokens) { return [int64]$Modelo.max_tokens }
    return 0
}

# ── rede ────────────────────────────────────────────────────────────────────
function Invoke-Api {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [string]$ApiKey = '',
        [string]$Metodo = 'GET',
        [string]$Corpo = '',
        [string]$Usuario = "cli-setup/$script:Versao",
        [int]$TimeoutSec = 30
    )
    $h = @{ 'User-Agent' = $Usuario }
    if ($ApiKey) {
        if ($Metodo -eq 'GET') { $h['x-api-key'] = $ApiKey } else { $h['Authorization'] = "Bearer $ApiKey" }
    }
    $args = @{
        Uri                = $Uri
        Method             = $Metodo
        Headers            = $h
        TimeoutSec         = $TimeoutSec
        SkipHttpErrorCheck = $true
        ErrorAction        = 'Stop'
    }
    if ($Corpo) {
        $args['Body'] = $Corpo
        $args['ContentType'] = 'application/json'
    }
    try {
        return Invoke-WebRequest @args
    } catch {
        return $null
    }
}

# Status HTTP puro, sem baixar o corpo inteiro.
function Get-HttpStatus {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [string]$ApiKey = '',
        [int]$TimeoutSec = 25
    )
    $r = Invoke-Api -Uri $Uri -ApiKey $ApiKey -TimeoutSec $TimeoutSec
    if ($null -eq $r) { return '000' }
    return [string][int]$r.StatusCode
}

# Lê /v1/models e guarda o objeto. Devolve $true se conseguiu.
function Initialize-Catalogo {
    param([Parameter(Mandatory)][string]$ApiKey)
    if ($script:CatalogoLido) { return $true }
    $r = Invoke-Api -Uri "$script:Base/v1/models" -ApiKey $ApiKey -TimeoutSec 25
    if ($null -eq $r) { return $false }
    if ([int]$r.StatusCode -ne 200) { return $false }
    try {
        $j = $r.Content | ConvertFrom-Json -ErrorAction Stop
    } catch { return $false }
    if (-not $j.PSObject.Properties['data']) { return $false }
    $script:CatalogoJson = $j
    $script:CatalogoLido = $true
    return $true
}

# Lê /v1/me e guarda os ids do plano. Sem isso o configurador gravaria modelos
# que respondem 403 ("está no Kodeo Ultra").
function Initialize-Plano {
    param([Parameter(Mandatory)][string]$ApiKey)
    if ($script:PlanoCarregado) { return $true }
    $r = Invoke-Api -Uri "$script:Base/v1/me" -ApiKey $ApiKey -TimeoutSec 20
    if ($null -eq $r -or [int]$r.StatusCode -ne 200) { return $false }
    try { $j = $r.Content | ConvertFrom-Json -ErrorAction Stop } catch { return $false }
    if (-not $j.PSObject.Properties['modelos']) { return $false }
    $ids = @()
    foreach ($m in @($j.modelos)) {
        if ($null -ne $m -and "$m" -ne '') { $ids += [string]$m }
    }
    $script:PlanoIds = $ids
    $script:PlanoCarregado = $true
    $script:PlanoJson = $j
    return ($ids.Count -gt 0)
}

function Get-PlanoJson { return $script:PlanoJson }

# ── catálogo do Codex ──────────────────────────────────────────────────────
# O catálogo que o Codex/ChatGPT lê (model_catalog_json) NÃO é o /v1/models.
# São objetos de schema próprio, com 36 campos que o app valida. O /v1/models
# traz 14, sem `slug` e sem `supported_reasoning_levels`, e o app recusa o
# arquivo inteiro — "failed to parse model_catalog_json". Por isso há um
# endpoint separado, /v1/codex/modelos, e é ele que alimenta este catálogo.
$script:CatalogoCodex = $null
$script:CatalogoCodexLido = $false

function Get-CatalogoCodexModelos {
    $d = $script:CatalogoCodex
    if ($null -eq $d) { return @() }
    if ($d.PSObject.Properties['models'] -and $d.models) { return @($d.models) }
    if ($d.PSObject.Properties['data'] -and $d.data) { return @($d.data) }
    return @()
}

function Initialize-CatalogoCodex {
    param([Parameter(Mandatory)][string]$ApiKey)
    if ($script:CatalogoCodexLido) { return $true }
    $r = Invoke-Api -Uri "$script:Base/v1/codex/modelos" -ApiKey $ApiKey -Metodo 'GET' -TimeoutSec 30
    if ($null -eq $r -or [int]$r.StatusCode -ne 200) { return $false }
    try { $j = $r.Content | ConvertFrom-Json -ErrorAction Stop } catch { return $false }
    if (-not $j.PSObject.Properties['models']) { return $false }
    $script:CatalogoCodex = $j
    $script:CatalogoCodexLido = $true
    return $true
}

# Modelos OpenAI do plano, a partir do catálogo do Codex (objetos íntegros).
function Get-ModelosCodex {
    $lista = @()
    foreach ($m in @(Get-CatalogoCodexModelos)) {
        $id = if ($m.PSObject.Properties['slug'] -and $m.slug) { [string]$m.slug }
              elseif ($m.PSObject.Properties['id'] -and $m.id) { [string]$m.id }
              else { '' }
        if (-not $id) { continue }
        if ((Get-Familia $id) -ne 'openai') { continue }
        if (-not (Test-NoPlano $id)) { continue }
        if ($id -match 'kodeo') { continue }
        $lista += ,$m
    }
    return @($lista | Sort-Object { -(Get-VersaoModelo $(if ($_.PSObject.Properties['slug']) { $_.slug } else { $_.id })) })
}

# ── consultas ───────────────────────────────────────────────────────────────
# Quantos modelos o catálogo tem (não o plano: o catálogo).
function Get-ModeloContagem {
    return @(Get-CatalogoModelos).Count
}

function Test-NoPlano {
    param([Parameter(Mandatory)][string]$Id)
    if ($script:PlanoIds.Count -eq 0) { return $true }   # sem plano: não filtra
    return ($script:PlanoIds -contains $Id)
}

# Todos os ids do catálogo, na ordem da API.
function Get-CatalogoIds {
    $out = @()
    foreach ($m in @(Get-CatalogoModelos)) {
        $id = Get-ModeloId $m
        if ($id) { $out += $id }
    }
    return $out
}

# O melhor modelo de um tier (opus|sonnet|haiku|fable), respeitando o plano.
# Devolve '' quando o plano não tem aquele tier — nunca troca por outro modelo.
function Get-MelhorTier {
    param([Parameter(Mandatory)][string]$Tier)
    $cand = @()
    foreach ($m in @(Get-CatalogoModelos)) {
        $id = Get-ModeloId $m
        if (-not $id) { continue }
        if ((Get-Tier $id) -ne $Tier) { continue }
        if (-not (Test-NoPlano $id)) { continue }
        $cand += $m
    }
    if ($cand.Count -eq 0) { return '' }
    $ordenado = @($cand | Sort-Object `
        @{ Expression = { if ((Get-ModeloId $_) -match '-kodeo') { 1 } else { 0 } } },
        @{ Expression = { if ((Get-ModeloId $_) -match '^kodeo-') { 1 } else { 0 } } },
        @{ Expression = { -(Get-VersaoModelo (Get-ModeloId $_)) } },
        @{ Expression = { -(Get-ModeloContexto $_) } },
        @{ Expression = { Get-ModeloId $_ } })
    return (Get-ModeloId $ordenado[0])
}

# Modelos Claude do plano, sem aliases de revenda, já ordenados. É a lista que
# o Claude Desktop e o Claude Code recebem.
function Get-ModelosAnthropic {
    $lista = @()
    foreach ($m in @(Get-CatalogoModelos)) {
        $id = Get-ModeloId $m
        if (-not $id) { continue }
        if ((Get-Familia $id) -ne 'anthropic') { continue }
        if (-not (Test-NoPlano $id)) { continue }
        $lista += $m
    }
    $ordenado = @($lista | Sort-Object `
        @{ Expression = { if ((Get-ModeloId $_) -match '-kodeo') { 1 } else { 0 } } },
        @{ Expression = { if ((Get-ModeloId $_) -match '^kodeo-') { 1 } else { 0 } } },
        @{ Expression = { -(Get-VersaoModelo (Get-ModeloId $_)) } },
        @{ Expression = { -(Get-ModeloContexto $_) } },
        @{ Expression = { Get-ModeloId $_ } })
    # Aliases de revenda duplicam o mesmo modelo no seletor do app. O nome
    # canônico já está na lista, então ficam de fora — a menos que sobre nada.
    $semRevenda = @($ordenado | Where-Object { (Get-ModeloId $_) -notmatch 'kodeo' })
    if ($semRevenda.Count -gt 0) { return $semRevenda }
    return $ordenado
}

# Modelos OpenAI do plano — o que o Codex e o ChatGPT Desktop recebem.
function Get-ModelosOpenAI {
    $lista = @()
    foreach ($m in @(Get-CatalogoModelos)) {
        $id = Get-ModeloId $m
        if (-not $id) { continue }
        if ((Get-Familia $id) -ne 'openai') { continue }
        if (-not (Test-NoPlano $id)) { continue }
        $lista += $m
    }
    return @($lista | Sort-Object { -(Get-VersaoModelo (Get-ModeloId $_)) })
}

# Modelos do plano para o OpenCode: todas as famílias, porque o seletor dele
# mostra o provedor junto.
function Get-ModelosPlano {
    $lista = @()
    foreach ($m in @(Get-CatalogoModelos)) {
        $id = Get-ModeloId $m
        if (-not $id) { continue }
        if (-not (Test-NoPlano $id)) { continue }
        $lista += $m
    }
    return $lista
}

# Padrão de uma ferramenta de código: opus → sonnet → haiku → fable → primeiro.
function Get-PadraoGeral {
    foreach ($t in @('opus', 'sonnet', 'haiku', 'fable')) {
        $m = Get-MelhorTier $t
        if ($m) { return $m }
    }
    $ids = Get-CatalogoIds
    if ($ids.Count -gt 0) { return $ids[0] }
    return ''
}

# Padrão do Codex/ChatGPT: só aceitam OpenAI. Usar o padrão global (que é
# Anthropic) gravava um modelo inválido no catálogo deles.
function Get-PadraoOpenAI {
    $openai = @(Get-ModelosOpenAI)
    if ($openai.Count -eq 0) { return '' }
    return (Get-ModeloId $openai[0])
}

# Resumo do plano por família, para a tela de modelos.
function Get-ResumoPlano {
    $r = [ordered]@{ Total = 0; Anthropic = 0; OpenAI = 0 }
    if ($script:PlanoIds.Count -eq 0) {
        $r.Total = (Get-ModeloContagem)
        return $r
    }
    foreach ($id in $script:PlanoIds) {
        $r.Total++
        switch (Get-Familia $id) {
            'anthropic' { $r.Anthropic++ }
            'openai'    { $r.OpenAI++ }
        }
    }
    return $r
}