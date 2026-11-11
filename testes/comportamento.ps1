#Requires -Version 7.0
<#
    testes/comportamento.ps1 — testes de comportamento do configurador.

    Roda os módulos e o instalador de verdade, com HOME isolado, e verifica o
    que importa para quem usa:

      1. configuração pré-existente do usuário é preservada
      2. o modelo padrão é o certo, nunca o primeiro da lista da API
      3. tier ausente não vira outro provedor
      4. rodar duas vezes não duplica
      5. OpenCode no formato V2
      6. Claude Desktop coerente e sem chave inventada
      7. o desfazer devolve o que era do usuário
      8. os caminhos de plataforma estão certos

    Uso:
      pwsh -File testes/comportamento.ps1
      pwsh -File testes/comportamento.ps1 -Chave ck_...      # com plano real
#>
[CmdletBinding()]
param(
    [string]$Chave = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Raiz = Split-Path -Parent $PSScriptRoot
. (Join-Path $Raiz 'ps/Plataforma.ps1')
. (Join-Path $Raiz 'ps/Json.ps1')
. (Join-Path $Raiz 'ps/Catalogo.ps1')
. (Join-Path $Raiz 'ps/Geradores.ps1')
. (Join-Path $Raiz 'ps/Desktop.ps1')
. (Join-Path $Raiz 'ps/Ui.ps1')

$script:Versao = '3.0'
$script:Base = if ($env:CLI_BASE) { $env:CLI_BASE } else { 'https://api.kodeo.com.br' }
$script:Falhas = 0
$script:MarcaIni = '# >>> kodeo >>>'
$script:MarcaFim = '# <<< kodeo <<<'

function ok    { param([string]$t) Write-Host "  $([char]27)[32mok$([char]27)[0m    $t" }
function falha { param([string]$t) Write-Host "  $([char]27)[31mFALHA$([char]27)[0m $t"; $script:Falhas++ }
function checa { param([string]$t, [bool]$cond) if ($cond) { ok $t } else { falha $t } }
function Find-PadraoNoTexto { param([string]$Texto, [string]$Padrao) return ($Texto -match "(?m)$Padrao") }

# ── HOME isolado ───────────────────────────────────────────────────────────
$Teste = Join-Path ([IO.Path]::GetTempPath()) ("cli-ps-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $Teste | Out-Null
$HomeOrig = $env:HOME
$env:HOME = Join-Path $Teste 'home'
New-Item -ItemType Directory -Force -Path $env:HOME | Out-Null

try {
    # ── catálogo ───────────────────────────────────────────────────────────
    if ($Chave) {
        if (-not (Initialize-Catalogo -ApiKey $Chave)) {
            Write-Host 'não consegui ler o catálogo da API — verifique a internet'
            exit 1
        }
        $null = Initialize-Plano -ApiKey $Chave
    } else {
        Write-Host "  $([char]27)[33maviso$([char]27)[0m sem -Chave: testando só os módulos offline"
    }

    Write-Host ''
    if ($Chave) {
        Write-Host ("modelos={0}  plano={1}  padrão={2}" -f (Get-ModeloContagem), (Get-PlanoIds).Count, (Get-PadraoGeral))
        Write-Host ''
    }

    # ══ 1. caminhos de plataforma ═════════════════════════════════════════
    Write-Host '1. Caminhos de plataforma'
    $cd3p = Get-Claude3pDir
    if (Test-Windows) {
        checa 'Claude-3p em LOCALAPPDATA' ($cd3p -like '*AppData\Local\Claude-3p*')
        checa 'config.toml em .codex'     ((Get-CodexConfig) -like '*\.codex\config.toml')
    } elseif (Test-MacOS) {
        checa 'Claude-3p em Application Support' ($cd3p -like '*Library/Application Support/Claude-3p*')
    } else {
        checa 'Claude-3p em .config' ($cd3p -like '*.config/Claude-3p*')
    }
    checa 'OpenCode em .config/opencode (todas as plataformas)' ((Get-OpenCodeConfig) -like '*.config*opencode*opencode.json')
    checa 'Claude Code em .claude/settings.json' ((Get-ClaudeCodeSettings) -like '*.claude*settings.json')
    Write-Host ''

    if ($Chave) {
        # ══ 2. modelo padrão ═════════════════════════════════════════════
        Write-Host '2. Modelo padrão é o certo, não o primeiro da API'
        $prim = (Get-CatalogoIds)[0]
        checa "a API lista $prim primeiro (cenário do bug)" ($prim -eq 'minimax-m2.7')
        $pad = Get-PadraoGeral
        checa "padrão é $pad (não o minimax)" ($pad -ne 'minimax-m2.7' -and $pad -ne '')
        $opus = Get-MelhorTier 'opus'
        checa "opus do plano: $opus" ($opus -ne '')
        # O padrão do Codex tem que ser OpenAI: usar o global (Anthropic)
        # gravava um modelo inválido no catálogo dele.
        $cx = Get-PadraoOpenAI
        checa "padrão OpenAI para o Codex: $cx" ($cx -match '^(gpt|codex|o[0-9])')
        checa 'nenhum modelo Anthropic no padrão do Codex' ((Get-Familia $cx) -eq 'openai')
        Write-Host ''

        # ══ 3. tier ausente ═════════════════════════════════════════════
        Write-Host '3. Tier ausente não vira outro provedor'
        $sonnet = Get-MelhorTier 'sonnet'
        if (-not $sonnet) {
            $envMapa = Get-ClaudeCodeEnv -Base $script:Base -Chave 'ck_teste' -Opus $opus -Sonnet $sonnet
            checa 'nenhum SONNET inventado (plano não tem Sonnet)' (-not $envMapa.Contains('ANTHROPIC_DEFAULT_SONNET_MODEL'))
        } else {
            ok "o plano tem Sonnet: $sonnet (nada a testar aqui)"
        }
        $envMapa2 = Get-ClaudeCodeEnv -Base $script:Base -Chave 'ck_teste' -Opus $opus
        checa 'OPUS aponta para o modelo Anthropic do plano' ($envMapa2['ANTHROPIC_DEFAULT_OPUS_MODEL'] -eq $opus)
        checa 'nenhuma variável aponta para grok' (-not ($envMapa2.Values -match 'grok'))
        Write-Host ''

        # ══ 4. Claude Desktop ═══════════════════════════════════════════
        Write-Host '4. Claude Desktop: chaves e coerência'
        $cfg = New-ClaudeDesktopConfig -Base $script:Base -Chave 'ck_teste' -Padrao $pad
        checa 'auth é x-api-key'              ($cfg['inferenceGatewayAuthScheme'] -eq 'x-api-key')
        checa 'discovery desligado'           ($cfg['modelDiscoveryEnabled'] -eq $false)
        checa 'primeiro modelo é o padrão'    ($cfg['inferenceModels'][0].name -eq $pad)
        checa 'primeiro modelo tem tier'      ([bool]$cfg['inferenceModels'][0]['anthropicFamilyTier'])
        checa 'primeiro modelo é default do tier' ($cfg['inferenceModels'][0]['isFamilyDefault'] -eq $true)
        checa 'sem chave inventada codeTabEnabled'   (-not $cfg.Contains('codeTabEnabled'))
        checa 'sem chave inventada pluginMarketplaces' (-not $cfg.Contains('pluginMarketplaces'))
        checa 'projetos habilitados'          ($cfg['projectsEnabled'] -eq $true)
        checa 'tarefas agendadas habilitadas' ($cfg['scheduledTasksEnabled'] -eq $true)
        checa 'só modelos Anthropic'          (@($cfg['inferenceModels'] | Where-Object { (Get-Familia $_.name) -ne 'anthropic' }).Count -eq 0)
        Write-Host ''

        # ══ 5. OpenCode V2 ══════════════════════════════════════════════
        Write-Host '5. OpenCode no formato V2'
        $mo = New-OpenCodeModelos
        $prov = New-OpenCodeProvider -Base $script:Base -Modelos $mo
        checa 'usa providers (V2), não provider (V1)' ($prov.Contains('providers') -and -not $prov.Contains('provider'))
        checa 'package do V2'  ($prov['providers']['kodeo']['package'] -eq '@opencode/ai/providers/openai-compatible')
        checa 'baseURL termina em /v1' ($prov['providers']['kodeo']['settings']['baseURL'] -match '/v1$')
        $primModelo = $mo[$mo.Keys[0]]
        checa 'modelos têm modelID e capabilities' ($primModelo.Contains('modelID') -and $primModelo['capabilities']['tools'] -eq $true)
        checa 'OpenCode recebe todos os modelos do plano' ($mo.Count -eq (Get-PlanoIds).Count)
        Write-Host ''
    }

    # ══ 6. JSON: preservação e atomicidade ═══════════════════════════════
    Write-Host '6. JSON preserva o que é do usuário e não corrompe'
    $f = Join-Path $Teste 'cfg.json'
    Write-FileAtomic -Path $f -Content '{"permissions":{"allow":["Bash(ls)"]},"env":{"MINHA":"valor"}}'
    $null = Update-JsonFile -Path $f -Operation merge -Value ([ordered]@{ env = [ordered]@{ ANTHROPIC_BASE_URL = 'https://x' } })
    checa 'merge manteve permissions do usuário' ((Get-JsonPath $f 'permissions.allow') -contains 'Bash(ls)')
    checa 'merge manteve variável do usuário no env' ((Get-JsonPath $f 'env.MINHA') -eq 'valor')
    checa 'merge adicionou a variável nova' ((Get-JsonPath $f 'env.ANTHROPIC_BASE_URL') -eq 'https://x')

    # array de 1 elemento não pode virar objeto ao reler
    $fa = Join-Path $Teste 'arr.json'
    Write-FileAtomic -Path $fa -Content '{"methods":[{"type":"key"}]}'
    $mA = Read-JsonMap $fa
    checa 'array de 1 elemento continua array' ($mA['methods'] -is [System.Array])

    # arquivo corrompido não é sobrescrito
    $fc = Join-Path $Teste 'corrompido.json'
    Write-FileAtomic -Path $fc -Content '{ isto nao e json'
    $antes = [IO.File]::ReadAllText($fc)
    $null = Update-JsonFile -Path $fc -Operation merge -Value ([ordered]@{ a = 1 }) -ErrorAction SilentlyContinue
    checa 'arquivo corrompido fica intacto' ($antes -eq [IO.File]::ReadAllText($fc))

    # sem BOM
    $bytes = [IO.File]::ReadAllBytes($f)
    checa 'grava sem BOM (o BOM quebra o leitor dos apps)' (-not ($bytes[0] -eq 239))
    Write-Host ''

    # ══ 7. idempotência, com o código real ══════════════════════════════
    Write-Host '7. Rodar duas vezes não duplica'
    $rc = Join-Path $env:HOME '.zshrc'
    Write-FileAtomic -Path $rc -Content "# linha do usuario`n"

    # Remove-BlocoMarcado é o que roda em produção: aplica duas vezes e confere.
    $ini = $script:MarcaIni; $fim = $script:MarcaFim
    for ($i = 0; $i -lt 2; $i++) {
        $t = [IO.File]::ReadAllText($rc)
        $corpo = Remove-BlocoMarcado -Texto $t -Ini $ini -Fim $fim
        $bloco = "$ini`nexport KODEO_API_KEY=`"ck_x`"`n$fim`n"
        Write-FileAtomic -Path $rc -Content ($corpo.TrimEnd() + "`n" + $bloco)
    }
    $n = ([regex]::Matches([IO.File]::ReadAllText($rc), [regex]::Escape($ini))).Count
    checa "bloco do shell não duplicou ($n)" ($n -eq 1)
    checa 'bloco preservou a linha do usuário' ((Find-PadraoNoTexto ([IO.File]::ReadAllText($rc)) 'linha do usuario'))

    # O mesmo com o merge de JSON: duas passadas não duplicam chave.
    $fm = Join-Path $Teste 'dup.json'
    Write-FileAtomic -Path $fm -Content '{"a":1}'
    $null = Update-JsonFile -Path $fm -Operation merge -Value ([ordered]@{ model = 'kodeo/x'; providers = [ordered]@{ kodeo = [ordered]@{ name = 'Kodeo' } } })
    $null = Update-JsonFile -Path $fm -Operation merge -Value ([ordered]@{ model = 'kodeo/x'; providers = [ordered]@{ kodeo = [ordered]@{ name = 'Kodeo' } } })
    $mj = Read-JsonMap $fm
    checa 'merge duas vezes mantém uma chave só' ($mj.Keys.Count -eq 3)
    checa 'merge preservou a chave do usuário (a)' ($mj['a'] -eq 1)
    Write-Host ''

    # ══ 7b. config.toml preserva o que o app escreveu ═════════════════════
    # O defeito mais caro que a suíte pegou. Em TOML, tudo que vem depois de um
    # cabeçalho de tabela pertence a ele — inclusive o que o próprio app
    # escreve. Com o provedor delimitado por marcas no fim do arquivo, o app
    # inseria notify, [plugins.*] e [mcp_servers.*] DENTRO do trecho marcado, e
    # o desfazer apagava tudo junto (49 linhas numa config real).
    Write-Host '7b. config.toml preserva o que o app escreveu'
    $cfgApp = @'
[model_providers.kodeo]
name = "Kodeo"
base_url = "https://api.kodeo.com.br/v1"
wire_api = "responses"

notify = ["/caminho/do/app", "turn-ended"]

[plugins."browser@openai-bundled"]
enabled = true

[mcp_servers.node_repl]
command = "/caminho/node_repl"
CODEX_CLI_PATH = "/caminho/codex"
'@
    $tc = Join-Path $Teste 'app.toml'
    Write-FileAtomic -Path $tc -Content $cfgApp

    $resto = Remove-BlocoMarcado -Texto $cfgApp -Ini $script:MarcaIni -Fim $script:MarcaFim -TabelaProvedor
    checa 'CODEX_CLI_PATH do app sobreviveu' ($resto -match 'CODEX_CLI_PATH')
    checa 'plugins do app sobreviveram'      ($resto -match 'browser@openai-bundled')
    checa 'nosso provedor saiu'              (-not ($resto -match 'model_providers\.kodeo'))
    # notify fica DEPOIS do cabeçalho da tabela em TOML: some junto, e é o certo.
    ok 'notify sai junto com a tabela (correto em TOML)'

    # Com o bloco do topo presente, ele sai e o resto fica.
    $comTopo = "# >>> kodeo >>>`nmodel = `"x`"`n# <<< kodeo <<<`n`ntheme = `"dark`"`n"
    $r2 = Remove-BlocoMarcado -Texto $comTopo -Ini $script:MarcaIni -Fim $script:MarcaFim
    checa 'bloco do topo sai'                 (-not ($r2 -match 'kodeo >>>'))
    checa 'o que vem depois do bloco fica'    ($r2 -match 'theme')
    Write-Host ''

    # ══ 7c. catálogo do Codex é válido ═══════════════════════════════════
    # O catálogo não é lista de nomes: o app valida cada modelo e recusa o
    # arquivo inteiro se faltar campo. E o base_instructions que a API serve
    # diz que o modelo é o "Codex CLI, da OpenAI" — substituí-lo muda a
    # identidade de fato, porque o arquivo é local e lido a cada execução.
    if ($Chave) {
        Write-Host '7c. catálogo do Codex é válido'
        $okCx = Initialize-CatalogoCodex -ApiKey $Chave
        checa 'li /v1/codex/modelos' ($okCx)
        if ($okCx) {
            $cat = New-CodexCatalogo -ModeloPadrao (Get-PadraoOpenAI)
            checa 'catálogo tem modelos' ($cat.models.Count -gt 0)
            if ($cat.models.Count -gt 0) {
                $m0 = $cat.models[0]
                checa "modelo tem $($m0.Keys.Count) campos (schema completo)" ($m0.Keys.Count -gt 20)
                checa 'tem slug (obrigatório)'                   ($m0.Contains('slug'))
                checa 'tem supported_reasoning_levels (obrigatório)' ($m0.Contains('supported_reasoning_levels'))
                $bi = if ($m0.Contains('base_instructions')) { [string]$m0['base_instructions'] } else { '' }
                checa 'base_instructions não diz que é da OpenAI' (-not ($bi -match 'led by OpenAI'))
                checa 'base_instructions aponta o gateway'        ($bi -match 'Kodeo')
                checa 'só modelos OpenAI no catálogo' (@($cat.models | Where-Object { (Get-Familia $_.slug) -ne 'openai' }).Count -eq 0)
            }
        }
        Write-Host ''
    }

    # ══ 8. TOML do Codex ═══════════════════════════════════════════════
    Write-Host '8. Bloco TOML do Codex'
    $t = Get-CodexBlocoTopo -Modelo 'gpt-6-sol' -CatalogoCaminho 'C:\Users\x\.codex\cli-setup-models.json'
    checa 'modelo no bloco' ($t -match 'model = "gpt-6-sol"')
    checa 'provider no bloco' ($t -match 'model_provider = "kodeo"')
    checa 'caminho do Windows normalizado para /' ($t -match 'C:/Users/x/\.codex/cli-setup-models\.json')
    $p = Get-CodexBlocoProvider -Base 'https://api.kodeo.com.br'
    checa 'base_url termina em /v1' ($p -match 'base_url = "https://api\.kodeo\.com\.br/v1"')
    checa 'wire_api é responses' ($p -match 'wire_api = "responses"')
    checa 'env_key é KODEO_API_KEY' ($p -match 'env_key = "KODEO_API_KEY"')
    Write-Host ''

    # ══ 9. Desktop: marketplaces e MCP ══════════════════════════════════
    Write-Host '9. Camadas do Desktop'
    $mk = Get-Marketplaces
    checa 'dois marketplaces oficiais' ($mk.Count -eq 2)
    checa 'marketplace segue o branch (sem ref fixo)' (@($mk | Where-Object { $_.Contains('ref') }).Count -eq 0)
    checa 'marketplace é anônimo (sem credencial)' (@($mk | Where-Object { $_.credentialKind -ne 'anonymous' }).Count -eq 0)
    $eg = Get-EgressHosts
    checa "egress padrão tem $($eg.Count) hosts" ($eg.Count -eq 11)
    $mr = Get-McpRemoto -Selecao 'linear,notion'
    checa 'seleção de remotos devolve 2' ($mr.Count -eq 2)
    checa 'remoto usa OAuth' ($mr[0].oauth -eq $true)
    checa 'seleção vazia devolve nada' (@(Get-McpRemoto -Selecao '').Count -eq 0)
    checa 'asana usa transporte sse' ((Get-McpRemoto -Selecao 'asana')[0].transport -eq 'sse')

    # A tela prometia "Sem pastas, só Memory e Sequential Thinking entram" e a
    # função devolvia @() antes de chegar neles: quem só dava Enter ficava sem
    # MCP nenhum. Só vale checar se os pacotes estão no cache do npm, senão a
    # asserção vira "tudo bem, nada entrou" e não prova nada.
    $semPasta = @(Get-McpLocal -Diretorios '')
    $nomesSem = @($semPasta | ForEach-Object { $_.name })
    if ($nomesSem.Count -eq 0) {
        checa 'sem pastas: nenhum MCP ainda no cache (nada a provar aqui)' $true
    } else {
        checa 'sem pastas não inclui Filesystem' (-not ($nomesSem -contains 'Filesystem'))
        checa "sem pastas entram $($nomesSem -join ', ')" `
            (($nomesSem -contains 'Memory') -and ($nomesSem -contains 'Sequential Thinking'))
    }
    $comPasta = @(Get-McpLocal -Diretorios 'C:/docs')
    $fs = @($comPasta | Where-Object { $_.name -eq 'Filesystem' })
    if ($fs.Count -eq 1) {
        checa 'com pasta o Filesystem recebe a pasta' (@($fs[0].args) -contains 'C:/docs')
    } else {
        checa 'com pasta: Filesystem ainda não está no cache (nada a provar aqui)' $true
    }
    Write-Host ''

    # ══ resumo ══════════════════════════════════════════════════════════
    Write-Host ("falhas: {0}" -f $script:Falhas)
    if ($script:Falhas -eq 0) { Write-Host "$([char]27)[32mTUDO OK$([char]27)[0m" }
    else { Write-Host "$([char]27)[31m$($script:Falhas) falha(s)$([char]27)[0m" }
}
finally {
    $env:HOME = $HomeOrig
    Remove-Item -LiteralPath $Teste -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:Falhas -gt 0) { exit 1 }
exit 0