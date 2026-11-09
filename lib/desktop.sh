#!/usr/bin/env bash
# lib/desktop.sh — configuração do Claude Desktop 3P para ficar equivalente ao app
# com assinatura Anthropic.
#
# O problema: ao apontar o app para um gateway, ele sai do modo Anthropic e perde
# conectores, skills e plugins. Tudo que ele recebia do Console da Anthropic deixa
# de existir. A config abaixo devolve essas três camadas por caminhos que FUNCIONAM
# sem infraestrutura da Anthropic, sem inventar nenhum host:
#
#   1. Conectores embutidos no app (server: websearch | github). Rodam como processo
#      local na máquina do usuário. Nada passa por host da Anthropic.
#   2. Skills oficiais pelo marketplace público anthropics/skills (Apache 2.0) —
#      o mesmo repositório que alimenta o Claude real: docx, pdf, pptx, xlsx.
#   3. Plugins de organização pelo diretório /Library/Application Support/Claude/org-plugins/.
#
# Cada valor foi conferido na documentação oficial
# (claude.com/docs/third-party/claude-desktop) ou é um repositório público real.

# ── Versão mais recente das skills ──────────────────────────────────────────
# A doc exige ref de 40 caracteres (commit SHA) quando installationPreference é
# auto_install/required. Branch e tag são recusados. Então resolvemos o SHA do
# HEAD em tempo de execução — nunca um valor fixo que envelhece.
# Guardamos em cache no diretório de config para não bater na API toda vez.
SKILLS_REPO="${KODEO_SKILLS_REPO:-anthropics/skills}"
SKILLS_REF_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/cli-setup/skills-ref"
SKILLS_REF_TTL=3600   # 1 hora

skills_ref() {
  local ref="${KODEO_SKILLS_REF:-}"
  if [ -n "$ref" ]; then printf '%s' "$ref"; return 0; fi

  # cache ainda válido?
  if [ -f "$SKILLS_REF_CACHE" ]; then
    local age
    age=$(( $(date +%s) - $(stat -f %m "$SKILLS_REF_CACHE" 2>/dev/null || stat -c %Y "$SKILLS_REF_CACHE" 2>/dev/null || echo 0) ))
    if [ "$age" -ge 0 ] && [ "$age" -lt "$SKILLS_REF_TTL" ]; then
      cat "$SKILLS_REF_CACHE"; return 0
    fi
  fi

  # sem KODEO_SKILLS_REF e sem cache: pergunta ao GitHub qual é o HEAD
  local sha
  sha=$(curl -s -m 15 -H 'accept: application/vnd.github+json' \
        "https://api.github.com/repos/$SKILLS_REPO/commits/main" 2>/dev/null \
        | sed -n 's/.*"sha": *"\([0-9a-f]\{40\}\)".*/\1/p' | head -1)
  case "$sha" in
    [0-9a-f]*) ;;
    *) echo "não consegui resolver a versão atual de $SKILLS_REPO" >&2; return 1 ;;
  esac
  mkdir -p "$(dirname "$SKILLS_REF_CACHE")" 2>/dev/null
  printf '%s' "$sha" >"$SKILLS_REF_CACHE" 2>/dev/null
  printf '%s' "$sha"
}

# ── Egress allowlist ────────────────────────────────────────────────────────
# Hosts que a sandbox do Cowork pode alcançar. Sem isso, Web Fetch e o shell
# dentro da sandbox não saem. Lista conservadora: só o necessário para instalar
# dependências e ler repositórios.
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
        deb.debian.org archive.ubuntu.com security.ubuntu.com ;;
    *)
      printf '%s\n' github.com api.github.com raw.githubusercontent.com \
        objects.githubusercontent.com \
        pypi.org files.pythonhosted.org \
        registry.npmjs.org npmjs.org ;;
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
# Só entra o conector que tem credencial: sem chave, ele não conecta e o app
# mostra erro de configuração em vez de funcionar.
desktop_mcp_builtin() { # BUSCA_PROVEDOR BUSCA_CHAVE GITHUB_CLIENT_ID → array JSON
  local prov="${1:-}" chave="${2:-}" gitid="${3:-}" out="" sep=""

  if [ -n "$prov" ] && [ -n "$chave" ]; then
    out="$out$sep{\"name\":\"Web search\",\"server\":\"websearch\",\"provider\":\"$prov\",\"headers\":{\"Authorization\":\"Bearer $chave\"},\"toolPolicy\":{\"web_search\":\"allow\"}}"
    sep=","
  fi
  if [ -n "$gitid" ]; then
    out="$out$sep{\"name\":\"GitHub\",\"server\":\"github\",\"clientId\":\"$gitid\",\"toolPolicy\":{\"merge_pull_request\":\"ask\",\"delete_repository\":\"blocked\"}}"
    sep=","
  fi
  printf '[%s]' "$out"
}

# ── Marketplaces de plugins ─────────────────────────────────────────────────
# O único público e oficial é anthropics/skills. "available" = aparece em
# Customize → Plugins → Organization para o usuário instalar. Não auto-instala,
# para não impor conteúdo sem o usuário pedir.
desktop_marketplaces_json() { # INCLUIR(1|0)
  if [ "${1:-1}" = "1" ]; then
    local ref; ref=$(skills_ref) || return 1
    printf '[{"source":"github","repo":"%s","ref":"%s","expectedName":"anthropic-agent-skills","credentialKind":"anonymous","installationPreference":"available"}]' \
      "$SKILLS_REPO" "$ref"
  else
    printf '[]'
  fi
}

# ── Diretório de plugins de organização ─────────────────────────────────────
org_plugins_dir() {
  if [ "$(uname -s)" = Darwin ]; then
    printf '/Library/Application Support/Claude/org-plugins'
  else
    printf '/opt/claude/org-plugins'
  fi
}