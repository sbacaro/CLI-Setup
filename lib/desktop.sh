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
desktop_mcp_builtin() { # BUSCA_PROVEDOR BUSCA_CHAVE GITHUB_CLIENT_ID → array JSON
  local prov="${1:-}" chave="${2:-}" gitid="${3:-}" out="" sep=""

  if [ -n "$prov" ] && [ -n "$chave" ]; then
    out="$out$sep{\"name\":\"Web search\",\"server\":\"websearch\",\"provider\":\"$prov\",\"headers\":{\"Authorization\":\"Bearer $chave\"},\"toolPolicy\":{\"web_search\":\"allow\"}}"
    sep=","
  fi
  if [ -n "$gitid" ]; then
    # readOnly não se combina com toolPolicy de escrita; as travas abaixo são
    # as ações irreversíveis de maior risco.
    out="$out$sep{\"name\":\"GitHub\",\"server\":\"github\",\"clientId\":\"$gitid\",\"toolPolicy\":{\"merge_pull_request\":\"ask\",\"delete_repository\":\"blocked\",\"force_push\":\"blocked\"}}"
    sep=","
  fi
  printf '[%s]' "$out"
}

# ── Diretório de plugins de organização ─────────────────────────────────────
org_plugins_dir() {
  if [ "$(uname -s)" = Darwin ]; then
    printf '/Library/Application Support/Claude/org-plugins'
  else
    printf '/opt/claude/org-plugins'
  fi
}