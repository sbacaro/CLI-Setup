# CLI Setup

Configurador de terminal que liga Claude Code, Claude Desktop, OpenCode, Codex
(CLI) e ChatGPT Desktop ao gateway, **lendo os modelos do seu plano em vez de
usar uma lista fixa**.

## O comando

| Sistema | Comando |
|---|---|
| macOS / Linux | `curl -fsSL https://raw.githubusercontent.com/sbacaro/CLI-Setup/main/instalar.sh \| CLI_KEY="ck_…" bash` |
| macOS / Linux (sem a chave) | `curl -fsSL https://raw.githubusercontent.com/sbacaro/CLI-Setup/main/instalar.sh \| bash` |
| Windows (PowerShell 7) | `.\instalar.ps1 -Chave "ck_…"` |
| Windows (sem a chave) | `.\instalar.ps1` |

Sem a chave, o **passo 1** do assistente pede.

## Plataformas

| Plataforma | Script | Como roda |
|---|---|---|
| macOS | `instalar.sh` | `bash` |
| Linux | `instalar.sh` | `bash` |
| Windows | `instalar.ps1` | PowerShell 7 (`pwsh`) |
| Windows (WSL) | `instalar.sh` | `bash`, dentro da distro |

O script PowerShell exige **PowerShell 7** (o `pwsh`), não o Windows PowerShell
5.1 que vem no sistema. O motivo é concreto: `Invoke-WebRequest
-SkipHttpErrorCheck`, que permite ler o status 401/403 da API sem virar
exceção, existe só a partir do 7.0. No 5.1 a chave inválida derrubaria o
assistente em vez de mostrar a mensagem.

No Windows, três coisas mudam de lugar — o script já trata cada uma:

| O quê | macOS / Linux | Windows |
|---|---|---|
| Claude Desktop 3P | `~/Library/Application Support/Claude-3p/` | `%LOCALAPPDATA%\Claude-3p\` |
| Variáveis do Claude Code | bloco no `.zshrc` / `.bashrc` | ambiente do usuário (`setx`) |
| Reinício do app | `osascript` + `open` | `Stop-Process` + `shell:AppsFolder` |

O Codex, o ChatGPT Desktop e o OpenCode usam os mesmos caminhos nas três
plataformas (`~/.codex/`, `~/.config/opencode/`), então não mudam.

> No Windows o app do ChatGPT e o Claude Desktop são pacotes da Store: a
> detecção usa `Get-AppxPackage`, porque não existe `.exe` num caminho fixo.

### Sem interação

Para provisionar uma máquina de uma vez (CI, imagem, onboarding):

```powershell
.\instalar.ps1 -NaoInterativo -Chave "ck_…"
.\instalar.ps1 -NaoInterativo -Chave "ck_…" -Ferramentas "claude-code,opencode"
.\instalar.ps1 -NaoInterativo -Desfazer -Chave "ck_…"
```

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
| **Codex** (CLI) | `https://api.kodeo.com.br/v1` | Responses | só OpenAI do plano |
| **ChatGPT Desktop** | `https://api.kodeo.com.br/v1` | Responses | só OpenAI do plano |
| **OpenCode** | `https://api.kodeo.com.br/v1` | OpenAI-compatible | todos do plano |

A URL sem `/v1` nos apps Anthropic é intencional: o SDK deles acrescenta
`/v1/messages`. Verificado na API — `/v1/messages` responde 200, `/messages` 404.

**Codex e ChatGPT Desktop são serviços separados na tela, mas compartilham o
mesmo `~/.codex/config.toml`.** A detecção de instalação é independente — o CLI
aparece em `command -v codex`, o app só como `/Applications/ChatGPT.app` — e
marcar os dois configura uma vez só, porque o alvo é o arquivo.

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
# macOS / Linux
bash testes/comportamento.sh
JSON_TOOL=python3 bash testes/comportamento.sh   # com python em vez de node

# confere cada chave do Claude Desktop contra a documentação oficial
CLI_TEST_KEY=ck_… bash testes/chaves.sh

# Windows / PowerShell
pwsh -File testes/comportamento.ps1
pwsh -File testes/comportamento.ps1 -Chave ck_…   # exercita o plano real
```

O teste de chaves existe porque o app descarta em silêncio uma chave que não
conhece: sem ele, uma chave inventada passaria como se estivesse configurada.

A suíte do PowerShell usa `HOME` isolado e testa o código real — não uma cópia
do comportamento. Os sete pontos: caminhos por plataforma, modelo padrão, tier
ausente, coerência do Claude Desktop, formato V2 do OpenCode, preservação do
JSON do usuário (inclusive arquivo corrompido, que não pode ser sobrescrito), e
idempotência.

## Estrutura

```
instalar.sh          assistente (5 telas) — macOS e Linux
instalar.ps1         assistente (5 telas) — Windows
lib/json.sh          leitura/escrita de JSON (node ou python)
lib/catalogo.sh      consulta /v1/models e /v1/me
lib/geradores.sh     monta a configuração de cada ferramenta
lib/opencode.sh      formato do OpenCode V2
lib/desktop.sh       conectores, marketplaces e egress do Claude Desktop
ps/Plataforma.ps1    caminhos por sistema (a camada que o bash não tinha)
ps/Json.ps1          JSON sem dependência externa
ps/Catalogo.ps1      consulta /v1/models e /v1/me
ps/Geradores.ps1     monta a configuração de cada ferramenta
ps/Desktop.ps1       conectores, marketplaces e egress
ps/Ui.ps1            teclado, moldura, logotipo, menus
testes/              testes de comportamento e de chaves
```

Os dois assistentes gravam exatamente a mesma configuração: o que muda é a
linguagem e os caminhos de cada sistema. A saída do Claude Desktop é
comparada chave por chave entre os dois.

Licença MIT.