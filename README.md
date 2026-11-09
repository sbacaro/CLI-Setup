# CLI Setup

Configurador de terminal que liga Claude Code, Claude Desktop, OpenCode e
Codex/ChatGPT Desktop ao gateway, **lendo os modelos do seu plano em vez de usar
uma lista fixa**.

## O comando

| Sistema | Comando |
|---|---|
| macOS / Linux | `curl -fsSL https://raw.githubusercontent.com/sbacaro/CLI-Setup/main/instalar.sh \| CLI_KEY="ck_…" bash` |
| macOS / Linux (sem a chave) | `curl -fsSL https://raw.githubusercontent.com/sbacaro/CLI-Setup/main/instalar.sh \| bash` |

Sem `CLI_KEY`, o **passo 1** do assistente pede a chave.

## Os quatro passos

1. **Chave** — validada na API antes de qualquer gravação.
2. **Ferramentas** — o que configurar ou desconfigurar.
3. **Modelos** — o plano é lido e resumido.
4. **Aplicar** — gravação guiada, com teste de conexão no fim.

## Endereço e modelos por app

Cada app fala o protocolo da sua família, no endereço que ele espera:

| App | URL base | Protocolo | Modelos |
|---|---|---|---|
| **Claude Code** | `https://api.kodeo.com.br` | Anthropic Messages | só Anthropic do plano |
| **Claude Desktop** | `https://api.kodeo.com.br` | Anthropic Messages | só Anthropic do plano |
| **ChatGPT / Codex** | `https://api.kodeo.com.br/v1` | Responses | só OpenAI do plano |
| **OpenCode** | `https://api.kodeo.com.br/v1` | OpenAI-compatible | todos do plano |

A URL sem `/v1` nos apps Anthropic é intencional: o SDK deles acrescenta
`/v1/messages`. Verificado na API — `/v1/messages` responde 200, `/messages` 404.

## Por que o catálogo vem do `/v1/me`

`GET /v1/models` devolve o **catálogo inteiro**, incluindo modelos de planos
superiores. Com uma chave do plano Max, ele lista 22 modelos, mas só 9 são
liberados — e um dos outros (`claude-fable-5.1`) responde **403: "está no Kodeo
Ultra"**.

A lista que vale está em `GET /v1/me`, campo `modelos`. O configurador usa ela
como fonte de verdade e filtra tudo por ali, inclusive a escolha do modelo
padrão.

## O que cada app recebe

- **Claude Code**: `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN` e
  `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL` **só para os tiers que o plano
  tem**. Um tier ausente fica sem variável, em vez de apontar para outro modelo.
- **Claude Desktop**: `inferenceModels` com `anthropicFamilyTier`,
  `isFamilyDefault`, `supports1m` e `labelOverride`, mais as capabilities do app
  (Chat, Cowork, Code, skills, plugins). Todas as chaves foram conferidas contra
  a documentação oficial de configuração do Claude Desktop 3P.
- **OpenCode**: formato **V2** (`providers` + `package` + `settings`), com todos
  os modelos do plano e o contexto real de cada um.
- **Codex / ChatGPT Desktop**: `model` explícito e um `model_catalog_json` com o
  padrão em primeiro lugar. Os nomes usam `GPT 5.5` (espaço), porque o app remove
  o prefixo `GPT-` do `display_name`.

## O que ele preserva

Toda gravação é mesclada e atômica (arquivo temporário + rename). Um JSON
corrompido faz o passo parar sem tocar no arquivo. Configuração que já existia
— permissões, variáveis, `files`, perfis, plugins — fica intacta.

## Desfazer

Rode de novo e marque o que aparece como `configurado`. O que for do usuário
volta como estava: o `config.toml` original, o modelo anterior do OpenCode, o
`settings.json` sem as nossas chaves.

## Variáveis

| Variável | Efeito |
|---|---|
| `CLI_KEY` | a chave; pula o passo 1 |
| `KODEO_KEY` | sinônimo, para compatibilidade |
| `CLI_BASE` | outro endereço de API (padrão `https://api.kodeo.com.br`) |
| `CLI_RAW` | de onde baixar `lib/` quando rodado por `curl \| bash` |
| `CLI_SEM_REINICIAR=1` | não reinicia os apps |
| `CLI_LINHAS` / `CLI_COLS` | força as dimensões do terminal |

## Testes

```sh
bash testes/comportamento.sh              # com node
JSON_TOOL=python3 bash testes/comportamento.sh   # com python
```

## Estrutura

```
instalar.sh          assistente (4 telas)
lib/json.sh          leitura/escrita de JSON (node ou python)
lib/catalogo.sh      consulta /v1/models e /v1/me
lib/geradores.sh     monta a configuração de cada ferramenta
lib/opencode.sh      formato do OpenCode V2
testes/              testes de comportamento
```

Licença MIT.