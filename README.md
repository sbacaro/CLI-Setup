# CLI Setup

Configurador de terminal que liga Claude Code, Claude Desktop, OpenCode e
Codex/ChatGPT Desktop ao gateway, **lendo os modelos do seu plano em vez de usar
uma lista fixa**.

## O comando

| Sistema | Comando |
|---|---|
| macOS / Linux | `curl -fsSL https://raw.githubusercontent.com/sbacaro/CLI-Setup/main/instalar.sh | CLI_KEY="ck_…" bash` |
| macOS / Linux (sem a chave) | `curl -fsSL https://raw.githubusercontent.com/sbacaro/CLI-Setup/main/instalar.sh | bash` |

Sem `CLI_KEY`, o **passo 1** do assistente pede a chave.

## Os cinco passos

1. **Chave** — validada na API antes de qualquer gravação.
2. **Ferramentas** — o que configurar ou desconfigurar.
3. **Modelos** — o catálogo do seu plano é lido e resumido.
4. **Desktop Completo** — MCP servers, skills, plugins e egress (só se Claude Desktop selecionado).
5. **Aplicar** — gravação guiada, com teste de conexão no fim.

## Claude Desktop Completo

O Claude Desktop 3P com gateway **vem vazio**: sem MCP, sem skills, sem plugins.
A etapa 4 adiciona tudo o que a versão oficial da Anthropic oferece:

### MCP Servers Disponíveis

| Servidor | Descrição |
|---|---|
| `filesystem` | Acesso a arquivos locais |
| `github` | Repositórios, issues, PRs |
| `brave-search` | Busca na web |
| `memory` | Memória persistente |
| `slack` | Workspace Slack |
| `postgres` | Banco PostgreSQL |
| `sqlite` | Banco SQLite |
| `aws` | AWS: S3, EC2, Lambda |
| `sequential-thinking` | Raciocínio avançado |

### Capabilities Habilitadas

- **Tabs**: Chat, Cowork, Code
- **Skills**: criação e scanning habilitados
- **Plugins**: marketplaces e uploads permitidos
- **Egress allowlist**: github.com, pypi.org, npmjs.org, etc.

## Por que o catálogo importa

O configurador não carrega lista de modelos. Ele consulta `GET /v1/models`
com a sua chave e usa o resultado para:

- **Claude Code**: define `ANTHROPIC_DEFAULT_OPUS_MODEL`, `..._SONNET_MODEL` e
  `..._HAIKU_MODEL` **só para os tiers que o plano tem**. Um tier ausente fica
  sem variável, em vez de apontar para outro modelo.
- **Claude Desktop**: grava `inferenceModels` completo, com
  `anthropicFamilyTier`, `isFamilyDefault`, `supports1m` e `labelOverride`, e
  `modelDiscoveryEnabled: false`. Sem isso o app filtra a lista, deixa os
  atalhos de tier vazios e o usuário configura tudo à mão.
- **OpenCode**: grava no formato **V2** (`providers` + `package` + `settings`),
  com todos os modelos e o contexto real de cada um.
- **Codex / ChatGPT Desktop**: fixa `model` explicitamente e instala um
  `model_catalog_json` com o padrão em primeiro lugar. Sem o `model` explícito,
  o app ordena pelo `priority` do catálogo e o primeiro modelo da lista vira o
  padrão.

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
| `CLI_RAW` | de onde baixar `lib/` quando rodado por `curl | bash` |
| `CLI_SEM_REINICIAR=1` | não reinicia os apps |
| `CLI_FULL_DESKTOP=1` | ativa modo completo para Desktop automaticamente |

## Testes

```sh
bash testes/comportamento.sh              # com node
JSON_TOOL=python3 bash testes/comportamento.sh   # com python
```

Cobrem: preservação de configuração existente, escolha do modelo padrão,
tier ausente sem redirecionamento, idempotência e o desfazer.

## Estrutura

```
instalar.sh          assistente (5 telas)
lib/json.sh          leitura/escrita de JSON (node ou python)
lib/catalogo.sh      consulta e interpreta /v1/models
lib/geradores.sh     monta a configuração de cada ferramenta
lib/opencode.sh      formato do OpenCode V2
lib/mcp_templates.sh templates de MCP servers
lib/desktop_completo.sh configurações avançadas do Desktop
testes/              testes de comportamento
```

Licença MIT.
