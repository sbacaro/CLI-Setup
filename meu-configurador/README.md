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

## Os cinco passos

1. **Chave** — validada na API antes de qualquer gravação.
2. **Ferramentas** — o que configurar ou desconfigurar.
3. **Modelos** — o plano é lido e resumido.
4. **Desktop** — conectores, skills e plugins que o app perde fora da assinatura.
5. **Aplicar** — gravação guiada, com teste de conexão no fim.

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

## Claude Desktop fora da assinatura

Ao apontar o app para um gateway, ele sai do modo Anthropic e deixa de receber
do Console da Anthropic: conectores, skills e plugins. O passo 4 devolve essas
camadas por caminhos que funcionam sem infraestrutura da Anthropic.

### Conectores, em três camadas

| Camada | O que é | Onde roda |
|---|---|---|
| **Embutidos no app** | `websearch`, `github` | processo local, na máquina do usuário |
| **Locais (stdio)** | filesystem, memory, sequential-thinking | `npx`, pacotes oficiais `@modelcontextprotocol` |
| **Remotos (OAuth)** | Linear, Notion, Sentry, Atlassian, Stripe, Asana | host do próprio fornecedor |

Os remotos foram verificados um a um: respondem 401 (existe, pede OAuth) e
servem `/.well-known/oauth-protected-resource` ou
`oauth-authorization-server`, que é o que o app exige para registrar o cliente
e abrir o navegador. Nenhum precisa de chave.

### Skills e plugins

Dois marketplaces oficiais da Anthropic no GitHub, Apache 2.0 — os mesmos que
alimentam o Claude real:

- `anthropics/skills` → docx, pdf, pptx, xlsx, skill-creator
- `anthropics/claude-code` → code-review, commit-commands, hookify

Aparecem em **Customize → Plugins → Organization**. O `ref` fica vazio para
rastrear o branch padrão: sempre a versão mais recente, sem valor que envelhece.

### O que não é possível

Conectores marcados **"Made by Anthropic"** são hospedados na infraestrutura da
Anthropic e só existem no app padrão. Nenhuma configuração muda isso. Também não
há `inferenceAnthropicBaseUrl`: o provider `anthropic` tem a URL fixa no código,
por isso o modo 3P existe.

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
| `CLI_BUSCA_PROVEDOR` | `brave`, `tavily` ou `exa` (busca na web) |
| `CLI_BUSCA_CHAVE` | chave do provedor de busca |
| `CLI_GITHUB_CLIENT_ID` | clientId do seu OAuth App do GitHub |
| `CLI_MCP_DIRS` | pastas liberadas para o Filesystem |
| `CLI_MCP_REMOTOS` | `linear,notion,sentry,atlassian,stripe,asana` |
| `CLI_EGRESS` | `minimo`, `padrao` ou `completo` |
| `CLI_LINHAS` / `CLI_COLS` | força as dimensões do terminal |

## Testes

```sh
bash testes/comportamento.sh              # com node
JSON_TOOL=python3 bash testes/comportamento.sh   # com python

# confere cada chave do Claude Desktop contra a documentação oficial
CLI_TEST_KEY=ck_… bash testes/chaves.sh
```

O teste de chaves existe porque o app descarta em silêncio uma chave que não
conhece: sem ele, uma chave inventada passaria como se estivesse configurada.

## Estrutura

```
instalar.sh          assistente (5 telas)
lib/json.sh          leitura/escrita de JSON (node ou python)
lib/catalogo.sh      consulta /v1/models e /v1/me
lib/geradores.sh     monta a configuração de cada ferramenta
lib/opencode.sh      formato do OpenCode V2
lib/desktop.sh       conectores, marketplaces e egress do Claude Desktop
testes/              testes de comportamento e de chaves
```

Licença MIT.