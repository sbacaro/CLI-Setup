#!/usr/bin/env bash
# lib/desktop.sh — configuração do Claude Desktop 3P para ficar equivalente ao app
# com assinatura Anthropic.
#
# O problema: ao apontar o app para um gateway, ele sai do modo Anthropic e perde
# conectores, skills e plugins. Tudo que ele recebia do Console da Anthropic deixa
# de existir. A config abaixo devolve essas camadas por caminhos que FUNCIONAM sem
# infraestrutura da Anthropic, sem inventar nenhum host:
#
#   1. Conectores embutidos no app (server: websearch | github). Rodam como processo
#      local na máquina do usuário. Nada passa por host da Anthropic.
#   2. Skills e plugins pelos marketplaces oficiais da Anthropic no GitHub,
#      Apache 2.0 — os mesmos repositórios que alimentam o Claude real.
#   3. Plugins de organização pelo diretório /Library/Application Support/Claude/org-plugins/.
#
# Cada valor foi conferido na documentação oficial
# (claude.com/docs/third-party/claude-desktop) ou é um repositório público real.

# ── Marketplaces oficiais da Anthropic ──────────────────────────────────────
# Ambos são repositórios públicos, sem autenticação, com .claude-plugin/marketplace.json.
# "ref" vazio rastreia o branch padrão: sempre a versão mais recente, sem valor
# fixo que envelhece. A doc exige SHA de 40 caracteres apenas quando
# installationPreference é auto_install/required — aqui é "available", então
# branch é aceito e preferível.
SKILLS_REPO="${KODEO_SKILLS_REPO:-anthropics/skills}"
SKILLS_NAME="anthropic-agent-skills"
CODE_REPO="${KODEO_CODE_PLUGINS_REPO:-anthropics/claude-code}"
CODE_NAME="claude-code-plugins"

# desktop_marketplaces_json → array JSON dos marketplaces permitidos.
# INCLUIR_SKILLS (1|0), INCLUIR_CODE (1|0)
desktop_marketplaces_json() {
  local sk="${1:-1}" cc="${2:-1}" out="" sep=""
  if [ "$sk" = "1" ]; then
    out="$out$sep{\"source\":\"github\",\"repo\":\"$SKILLS_REPO\",\"expectedName\":\"$SKILLS_NAME\",\"credentialKind\":\"anonymous\",\"installationPreference\":\"available\"}"
    sep=","
  fi
  if [ "$cc" = "1" ]; then
    out="$out$sep{\"source\":\"github\",\"repo\":\"$CODE_REPO\",\"expectedName\":\"$CODE_NAME\",\"credentialKind\":\"anonymous\",\"installationPreference\":\"available\"}"
    sep=","
  fi
  printf '[%s]' "$out"
}

# ── Egress allowlist ────────────────────────────────────────────────────────
# Hosts que a sandbox do Cowork pode alcançar. Sem isso, Web Fetch e o shell
# dentro da sandbox não saem. Inclui os hosts do marketplace (github) e os
# provedores de busca (o conector websearch roda fora da sandbox, mas o Web
# Fetch dos resultados precisa passar).
desktop_egress_hosts() { # minimo|padrao|completo
  case "${1:-padrao}" in
    minimo)
      printf '%s\n' github.com api.github.com ;;
    completo)
      printf '%s\n' github.com api.github.com raw.githubusercontent.com \
        objects.githubusercontent.com codeload.github.com \
        gitlab.com bitbucket.org \
        pypi.org files.pythonhosted.org \
        registry.npmjs.org npmjs.org \
        deb.debian.org archive.ubuntu.com security.ubuntu.com \
        api.search.brave.com api.tavily.com api.exa.ai ;;
    *)
      printf '%s\n' github.com api.github.com raw.githubusercontent.com \
        objects.githubusercontent.com \
        pypi.org files.pythonhosted.org \
        registry.npmjs.org npmjs.org \
        api.search.brave.com api.tavily.com api.exa.ai ;;
  esac
}

desktop_egress_json() { # minimo|padrao|completo
  local primeiro=1 h
  printf '['
  for h in $(desktop_egress_hosts "${1:-padrao}"); do
    [ "$primeiro" -eq 0 ] && printf ',' || primeiro=0
    printf '"%s"' "$h"
  done
  printf ']'
}

# ── Conectores embutidos no app ─────────────────────────────────────────────
# Cada entrada usa "server" — nunca url/transport/command junto. A doc diz que
# uma entrada que mistura "server" com campo remoto é rejeitada.
# Só entra o conector que tem credencial: sem chave ele não conecta e o app
# mostra erro de configuração em vez de funcionar.
org_plugins_dir() {
  if [ "$(uname -s)" = Darwin ]; then
    printf '/Library/Application Support/Claude/org-plugins'
  else
    printf '/opt/claude/org-plugins'
  fi
}

# ── MCP local via npx ───────────────────────────────────────────────────────
# A doc exige que "command" seja caminho ABSOLUTO do executável. npx resolve
# isso, mas o pacote só está disponível depois do primeiro download. Por isso
# pré-aquecemos: npx -y <pacote> --version (ou --help) baixa para o cache do
# npm, e aí o app encontra o pacote já em disco quando for conectar.
# Só incluímos o servidor cujo pacote baixou de verdade. Sem isso o app
# mostraria erro de conexão em vez de funcionar.

# npx_preaquecer PACOTE → 0 se o pacote está no cache do npm
npx_preaquecer() {
  local pacote="$1"
  command -v npx >/dev/null 2>&1 || return 1
  npm ls -g --depth=0 "$pacote" >/dev/null 2>&1 && return 0
  # --help sai não-zero em alguns pacotes; o que interessa é o download.
  timeout 120 npx -y "$pacote" --help >/dev/null 2>&1 || true
  npm cache ls "$pacote" 2>/dev/null | grep -q . && return 0
  # fallback: se o npx rodou, o pacote está em _npx
  ls "$HOME/.npm/_npx" >/dev/null 2>&1 && return 0
  return 1
}

# npx_caminho PACOTE COMANDO → caminho absoluto do binário dentro do cache do npm.
# Prefere o binário de _npx/<hash>/node_modules/.bin/.
npx_binario() {
  local pacote="$1" bin="$2" p
  for p in "$HOME/.npm/_npx"/*/node_modules/.bin/"$bin"; do
    [ -x "$p" ] && { printf '%s' "$p"; return 0; }
  done
  # global
  command -v "$bin" >/dev/null 2>&1 && { command -v "$bin"; return 0; }
  return 1
}

# desktop_mcp_local DIRETORIOS → array JSON de servidores stdio locais reais.
# Só entram os que resolvem para um binário absoluto existente.
desktop_mcp_local() { # DIRETORIOS (separados por vírgula; vazio = não inclui)
  local dirs="${1:-}" out="" sep="" bin

  [ -z "$dirs" ] && { printf '[]'; return 0; }

  if npx_preaquecer "@modelcontextprotocol/server-filesystem"; then
    bin=$(npx_binario "@modelcontextprotocol/server-filesystem" mcp-server-filesystem)
    if [ -n "$bin" ]; then
      local argsjson="" d
      for d in $(printf '%s' "$dirs" | tr ',' ' '); do
        [ -z "$d" ] && continue
        argsjson="$argsjson${argsjson:+,}\"$d\""
      done
      out="$out$sep{\"name\":\"Filesystem\",\"transport\":\"stdio\",\"command\":\"$bin\",\"args\":[${argsjson:-$HOME}],\"toolPolicy\":{\"write_file\":\"ask\",\"delete_file\":\"ask\"}}"
      sep=","
    fi
  fi

  if npx_preaquecer "@modelcontextprotocol/server-memory"; then
    bin=$(npx_binario "@modelcontextprotocol/server-memory" mcp-server-memory)
    [ -n "$bin" ] && { out="$out$sep{\"name\":\"Memory\",\"transport\":\"stdio\",\"command\":\"$bin\",\"args\":[]}"; sep=","; }
  fi

  if npx_preaquecer "@modelcontextprotocol/server-sequential-thinking"; then
    bin=$(npx_binario "@modelcontextprotocol/server-sequential-thinking" mcp-server-sequential-thinking)
    [ -n "$bin" ] && { out="$out$sep{\"name\":\"Sequential Thinking\",\"transport\":\"stdio\",\"command\":\"$bin\",\"args\":[]}"; sep=","; }
  fi

  printf '[%s]' "$out"
}