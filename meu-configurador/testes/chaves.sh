#!/usr/bin/env bash
# testes/chaves.sh — confere cada chave que gravamos contra a documentação oficial.
# Falha se alguma chave não existir: uma chave inventada é ignorada pelo app
# silenciosamente (a doc diz que ele descarta chaves desconhecidas), então o
# usuário acharia que configurou algo que não existe.
set -u
cd "$(dirname "$0")/.." || exit 1

DOC="${CLI_DOC:-/tmp/cdconf.md}"
if [ ! -f "$DOC" ]; then
  curl -fsSL -m 45 https://claude.com/docs/third-party/claude-desktop/configuration.md -o "$DOC" || {
    echo "sem a documentação: pule este teste"; exit 0; }
fi

K="${CLI_TEST_KEY:-}"
if [ -z "$K" ]; then
  echo "defina CLI_TEST_KEY para rodar este teste"; exit 0
fi

export JSON_TOOL="${JSON_TOOL:-node}"
. lib/json.sh
. lib/catalogo.sh
. lib/geradores.sh
. lib/desktop.sh

BASE="${CLI_BASE:-https://api.kodeo.com.br}"
catalogo_carregar "$K" || { echo "falha no catálogo"; exit 1; }
cat_plano_carregar "$K"
export CATALOGO_JSON CATALOGO_LIDO CAT_PLANO_IDS JSON_TOOL
PADRAO_ID=$(cat_padrao_geral)
MK=$(desktop_marketplaces_json 1 1)
EG=$(desktop_egress_json padrao)

KEYS=$(printf '%s' "$CATALOGO_JSON" | \
  CAT_BASE="$BASE" CAT_CHAVE="$K" CAT_OPUS="$PADRAO_ID" \
  CAT_MARKETPLACES="$MK" CAT_EGRESS="$EG" \
  catalogo_gerar_claude | catalogo_chaves)

falhas=0
total=0
for k in $KEYS; do
  total=$((total+1))
  if ! grep -qE "\[\`$k\`\]|^#### \`$k\`" "$DOC"; then
    printf '  ✗ INVENTADA: %s\n' "$k"
    falhas=$((falhas+1))
  fi
done

printf '\n  %s chaves, %s inventadas\n' "$total" "$falhas"
[ "$falhas" -eq 0 ]