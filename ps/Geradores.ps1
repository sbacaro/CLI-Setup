# ps/Geradores.ps1 — monta as configurações de cada ferramenta a partir do
# catálogo do plano.
#
# Regra de ouro (veio da versão bash e vale aqui): nenhum modelo é inventado.
# Tudo vem do catálogo, e o padrão é escolhido por critério explícito.
#
# Cada função devolve um objeto (mapa ordenado) pronto para virar JSON/TOML.
# Antes, cada gerador tinha duas implementações (node e python3) que precisavam
# concordar. Aqui há uma só, o que elimina a chance de as duas divergirem.

Set-StrictMode -Version Latest

# ── Claude Desktop: config do Claude Desktop 3P ────────────────────────────
# Chaves conferidas contra docs oficiais
# (claude.com/docs/third-party/claude-desktop/configuration):
#   - não existe "codeTabEnabled": o Code é ligado por isClaudeCodeForDesktopEnabled;
#   - não existe "pluginMarketplaces": o correto é allowedPluginMarketplaces;
#   - o app descarta em silêncio chave que não reconhece, então chave inventada
#     não dá erro — só não faz nada. Por isso cada uma abaixo tem origem na doc.
function New-ClaudeDesktopConfig {
    param(
        [Parameter(Mandatory)][string]$Base,
        [Parameter(Mandatory)][string]$Chave,
        [string]$Padrao = '',
        [array]$Marketplaces = @(),
        [array]$Egress = @(),
        [array]$McpLocal = @(),
        [array]$McpRemoto = @(),
        [string]$BuscaProvedor = '',
        [string]$BuscaChave = '',
        [string]$GithubClientId = ''
    )

    $modelos = @(Get-ModelosAnthropic)
    $lista = @()
    $padraoTier = [ordered]@{}

    foreach ($m in $modelos) {
        $id = Get-ModeloId $m
        $tier = Get-Tier $id
        $nome = (Get-ModeloNome $m) -replace '\s*\(kodeo\)\s*$', ''
        $o = [ordered]@{ name = $id; labelOverride = $nome.Trim() }
        if ($tier) {
            $o['anthropicFamilyTier'] = $tier
            if (-not $padraoTier.Contains($tier)) {
                $padraoTier[$tier] = $id
                $o['isFamilyDefault'] = $true
            }
        }
        if ((Get-ModeloContexto $m) -ge 1000000) { $o['supports1m'] = $true }
        $lista += ,$o
    }

    # O padrão vai em primeiro na lista: o app usa o primeiro item como modelo
    # inicial quando o usuário abre o seletor.
    $padraoFinal = $Padrao
    if (-not $padraoFinal -and $padraoTier.Contains('opus')) { $padraoFinal = $padraoTier['opus'] }
    if (-not $padraoFinal -and $lista.Count -gt 0) { $padraoFinal = $lista[0].name }

    if ($padraoFinal) {
        $prim = $lista | Where-Object { $_.name -eq $padraoFinal } | Select-Object -First 1
        if ($prim) {
            $prim['anthropicFamilyTier'] = Get-Tier $padraoFinal
            $prim['isFamilyDefault'] = $true
            if ((Get-ModeloContexto ($modelos | Where-Object { (Get-ModeloId $_) -eq $padraoFinal } | Select-Object -First 1)) -ge 1000000) {
                $prim['supports1m'] = $true
            }
            $resto = @($lista | Where-Object { $_.name -ne $padraoFinal })
            $lista = @($prim) + $resto
        }
    }

    $cfg = [ordered]@{
        inferenceProvider           = 'gateway'
        inferenceCredentialKind     = 'static'
        inferenceGatewayBaseUrl     = $Base
        inferenceGatewayApiKey      = $Chave
        inferenceGatewayAuthScheme  = 'x-api-key'
        modelDiscoveryEnabled       = $false
        inferenceModels             = $lista
    }

    # Abas e capacidades do app.
    $cfg['chatTabEnabled'] = $true
    $cfg['coworkTabEnabled'] = $true
    $cfg['isClaudeCodeForDesktopEnabled'] = $true
    $cfg['autoModeEnabled'] = $true

    # Skills e plugins.
    $cfg['skillCreationEnabled'] = $true
    $cfg['skillScanningEnabled'] = $true
    $cfg['disableBundledSkills'] = $false
    $cfg['userPluginMarketplacesEnabled'] = $true
    $cfg['userPluginUploadsEnabled'] = $true

    # MCP local.
    $cfg['isLocalDevMcpEnabled'] = $true
    $cfg['mcpPersistentAlwaysAllowEnabled'] = $true

    # Features que a config 3P também controla. Sem elas o app fica funcional
    # mas capado: sem projetos, sem tarefas agendadas, sem navegador embutido,
    # sem manter a máquina acordada durante uma tarefa.
    $cfg['projectsEnabled'] = $true
    $cfg['scheduledTasksEnabled'] = $true
    $cfg['keepAwakeEnabled'] = $true
    $cfg['builtinBrowserEnabled'] = $true
    $cfg['quickEntryScreenshotsEnabled'] = $true
    $cfg['quickEntryFileSharingEnabled'] = $true

    # Conectores embutidos no app. Só entra o que tem credencial: um conector
    # declarado sem chave aparece quebrado na interface.
    $mcp = @()
    if ($BuscaProvedor -and $BuscaChave) {
        $mcp += ,([ordered]@{
            name       = 'Web search'
            server     = 'websearch'
            provider   = $BuscaProvedor
            headers    = [ordered]@{ Authorization = "Bearer $BuscaChave" }
            toolPolicy = [ordered]@{ web_search = 'allow' }
        })
    }
    if ($GithubClientId) {
        $mcp += ,([ordered]@{
            name       = 'GitHub'
            server     = 'github'
            clientId   = $GithubClientId
            toolPolicy = [ordered]@{
                merge_pull_request = 'ask'
                delete_repository  = 'blocked'
                force_push         = 'blocked'
            }
        })
    }
    foreach ($x in $McpLocal)   { $mcp += ,$x }
    foreach ($x in $McpRemoto)  { $mcp += ,$x }
    if ($mcp.Count -gt 0) { $cfg['managedMcpServers'] = $mcp }

    if ($Marketplaces.Count -gt 0) { $cfg['allowedPluginMarketplaces'] = @($Marketplaces) }
    if ($Egress.Count -gt 0)       { $cfg['coworkEgressAllowedHosts'] = @($Egress) }

    return $cfg
}

# ── OpenCode: todos os modelos do plano, com contexto real ──────────────────
# O OpenCode é o único app que recebe a lista inteira (todas as famílias),
# porque o seletor dele mostra o provedor junto. Mas só o que o plano libera:
# o catálogo lista planos superiores, e um deles responde 403.
#
# Formato V2 (v2.x): "providers" + "package" + "settings". O formato antigo
# ("provider" + "npm") é ignorado pelo V2 e o provedor não aparece.
function New-OpenCodeModelos {
    $out = [ordered]@{}
    foreach ($m in @(Get-ModelosPlano)) {
        $id = Get-ModeloId $m
        if (-not $id) { continue }
        $ctx = Get-ModeloContexto $m
        if ($ctx -le 0) { $ctx = 200000 }
        $saida = Get-ModeloSaida $m
        if ($saida -le 0) { $saida = 32000 }
        $capsIn = @('text')
        if ($m.PSObject.Properties['capabilities'] -and $m.capabilities) {
            $c = $m.capabilities
            if ($c.PSObject.Properties['image_input'] -and $c.image_input -and $c.image_input.supported) { $capsIn += 'image' }
            if ($c.PSObject.Properties['pdf_input']   -and $c.pdf_input   -and $c.pdf_input.supported)   { $capsIn += 'pdf' }
        }
        $caps = [ordered]@{ tools = $true; input = $capsIn; output = @('text') }
        if ($m.PSObject.Properties['capabilities'] -and $m.capabilities -and
            $m.capabilities.PSObject.Properties['thinking'] -and $m.capabilities.thinking -and
            $m.capabilities.thinking.supported) {
            $caps['reasoning'] = $true
        }
        $nome = (Get-ModeloNome $m) -replace '\s*\(kodeo\)\s*$', ''
        $out[$id] = [ordered]@{
            modelID      = $id
            name         = $nome.Trim()
            limit        = [ordered]@{ context = $ctx; output = $saida }
            capabilities = $caps
        }
    }
    return $out
}

# O objeto do provedor, no formato que o V2 lê. A chave entra por variável de
# ambiente (env), não no arquivo: o V2 guarda credencial no SQLite do servidor
# e a documentação proíbe editar esse banco à mão.
function New-OpenCodeProvider {
    param([Parameter(Mandatory)][string]$Base, [Parameter(Mandatory)]$Modelos)
    return [ordered]@{
        providers = [ordered]@{
            kodeo = [ordered]@{
                name    = 'Kodeo'
                env     = @('KODEO_API_KEY')
                package = '@opencode/ai/providers/openai-compatible'
                settings = [ordered]@{ baseURL = "$Base/v1" }
                models   = $Modelos
            }
        }
    }
}

# A integração que dá à chave um lugar na TUI (/connect). Sem isso o provedor
# aparece, mas não há onde colar a chave.
function New-OpenCodeIntegracao {
    return [ordered]@{
        integrations = [ordered]@{
            kodeo = [ordered]@{
                name    = 'Kodeo'
                methods = @([ordered]@{ type = 'key'; label = 'Kodeo API key' })
            }
        }
    }
}

# ── Claude Code: variáveis por tier ────────────────────────────────────────
# Só define a variável do tier que existe no plano. Tier ausente fica sem
# variável, em vez de apontar para outro modelo — era isso que fazia "Sonnet"
# virar outro provedor.
function Get-ClaudeCodeEnv {
    param(
        [Parameter(Mandatory)][string]$Base,
        [Parameter(Mandatory)][string]$Chave,
        [string]$Opus = '',
        [string]$Sonnet = '',
        [string]$Haiku = ''
    )
    $env_ = [ordered]@{}
    $env_['ANTHROPIC_BASE_URL']   = $Base
    $env_['ANTHROPIC_AUTH_TOKEN'] = $Chave
    if ($Opus)   { $env_['ANTHROPIC_DEFAULT_OPUS_MODEL']   = $Opus }
    if ($Sonnet) { $env_['ANTHROPIC_DEFAULT_SONNET_MODEL'] = $Sonnet }
    if ($Haiku)  { $env_['ANTHROPIC_DEFAULT_HAIKU_MODEL']  = $Haiku }
    return $env_
}

# ── Codex / ChatGPT Desktop: catálogo de modelos ───────────────────────────
# O app lê um arquivo de catálogo próprio (model_catalog_json). Formato: uma
# lista "models", cada um com slug e display_name. O padrão vai em primeiro.
# Instruções do Codex/ChatGPT. O /v1/codex/modelos traz 20 mil caracteres de
# base_instructions dizendo "You are a coding agent running in the Codex CLI
# ... an open source project led by OpenAI". É a origem do "Sou o Codex CLI".
# O arquivo de catálogo é local e o app o lê a cada execução, então substituir
# esse texto muda a identidade de fato. Vazio desliga a substituição.
$script:CodexInstrucoes = if ($null -ne $env:KODEO_CODEX_INSTRUCOES) {
    $env:KODEO_CODEX_INSTRUCOES
} else {
    'You are a coding agent. You run inside the Kodeo gateway, not OpenAI. Never claim to be Codex CLI or a product of OpenAI. If asked who you are, say you are an AI assistant accessed through the Kodeo gateway. Reply in the language of the user.'
}

# Monta o catálogo que model_catalog_json aponta.
#
# O catálogo NÃO é uma lista de nomes: o app valida cada modelo contra um
# schema e recusa o arquivo inteiro se faltar campo ("failed to parse
# model_catalog_json: missing field supported_reasoning_levels"). Gravar só
# {slug, display_name, context} descartava 34 campos e deixava o Codex sem
# catálogo, em silêncio. Aqui o objeto vai íntegro; só o que é nosso muda.
function New-CodexCatalogo {
    param([Parameter(Mandatory)][string]$ModeloPadrao)

    $lista = @()
    foreach ($m in @(Get-ModelosCodex)) {
        $id = if ($m.PSObject.Properties['slug']) { [string]$m.slug } else { Get-ModeloId $m }
        if (-not $id) { continue }

        # Repassa o objeto cru (todos os campos que o schema exige).
        $obj = [ordered]@{}
        foreach ($p in $m.PSObject.Properties) {
            $obj[$p.Name] = ConvertTo-OrderedMap $p.Value
        }
        if ($obj.Contains('display_name') -and $obj['display_name'] -is [string]) {
            $n = $obj['display_name'] -replace '^GPT-', 'GPT '
            $n = $n -replace '\s*\(kodeo\)\s*$', ''
            $obj['display_name'] = $n.Trim()
        }
        if ($script:CodexInstrucoes) { $obj['base_instructions'] = $script:CodexInstrucoes }
        $lista += ,$obj
    }

    # O padrão primeiro: é o que o app mostra selecionado na primeira abertura.
    $prim = $lista | Where-Object { $_.slug -eq $ModeloPadrao } | Select-Object -First 1
    if ($prim) {
        $lista = @($prim) + @($lista | Where-Object { $_.slug -ne $ModeloPadrao })
    }
    if ($lista.Count -eq 0) { return [ordered]@{ models = @() } }
    return [ordered]@{ models = $lista }
}

# Bloco TOML do topo do config.toml, com as marcas que o desfazer reconhece.
function Get-CodexBlocoTopo {
    param(
        [Parameter(Mandatory)][string]$Modelo,
        [Parameter(Mandatory)][string]$CatalogoCaminho
    )
    $ini = '# >>> kodeo >>>'
    $fim = '# <<< kodeo <<<'
    # O caminho do catálogo vai entre aspas simples no TOML: no Windows ele tem
    # "\", que o TOML trataria como escape em string normal.
    $cat = $CatalogoCaminho -replace '\\', '/'
    return @"
$ini
model = "$Modelo"
model_provider = "kodeo"
model_catalog_json = "$cat"
$fim
"@
}

# Bloco TOML do provider. Fica no fim do arquivo, porque no TOML tudo que vem
# depois de um cabeçalho de tabela pertence a ele.
function Get-CodexBlocoProvider {
    param([Parameter(Mandatory)][string]$Base)
    # Sem marcas de comentário em volta. Em TOML tudo que vem depois de um
    # cabeçalho de tabela pertence a ele — inclusive o que o próprio app
    # escrever ali depois. Com marcas no fim do arquivo, o app inseria
    # notify, [plugins.*] e [mcp_servers.*] DENTRO do trecho marcado, e o
    # desfazer apagava tudo junto (49 linhas na config real). O escopo do
    # provedor é a tabela [model_providers.kodeo], e é por ela que a remoção
    # se orienta.
    return @"
[model_providers.kodeo]
name = "Kodeo"
base_url = "$Base/v1"
wire_api = "responses"
env_key = "KODEO_API_KEY"
requires_openai_auth = false
http_headers = { "x-openai-actor-authorization" = "kodeo" }
"@
}