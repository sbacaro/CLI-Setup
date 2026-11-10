#!/usr/bin/env bash
# testes/comportamento.sh — testes de comportamento que importam para quem usa
# o configurador:
#   1. rodar duas vezes não duplica nem corrompe
#   2. um config.toml/settings.json que o usuário já tinha é preservado
#   3. o modelo padrão nunca cai no MiniMax por acidente
#   4. o desfazer devolve o que era do usuário
#
# Como roda: isola HOME num diretório temporário, carrega as libs e as funções
# de aplicação extraídas do instalar.sh, e aplica de verdade.
#
#   bash testes/comportamento.sh
#   JSON_TOOL=python3 bash testes/comportamento.sh
#   CLI_TEST_KEY=ck_… bash testes/comportamento.sh   (usa a chave real)
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO" || exit 1

export BASE="${CLI_BASE:-https://api.kodeo.com.br}"
export JSON_TOOL="${JSON_TOOL:-node}"
export MARCA_INI="# >>> kodeo >>>" MARCA_FIM="# <<< kodeo <<<"
export VERSAO="2.3" FALHAS=0

# O instalar.sh usa estas variáveis de estilo e desenho; nos testes elas não
# precisam de cor nem de cursor.
ACC_F="" R="" OK="" ERR="" G="" W="" B="" SPIN='x'
limpa_linha() { :; }; pausa() { :; }; tela() { :; }; rodape() { :; }
caixa_topo() { :; }; caixa_linha() { :; }; caixa_fundo() { :; }
cursor_on() { :; }; cursor_off() { :; }; tecla() { printf 'enter'; }

. "$REPO/lib/json.sh"
. "$REPO/lib/catalogo.sh"
. "$REPO/lib/geradores.sh"
. "$REPO/lib/opencode.sh"
. "$REPO/lib/desktop.sh"

FALHOU=0
ok()    { printf '  \033[32mok\033[0m    %s\n' "$1"; }
falha() { printf '  \033[31mFALHA\033[0m %s\n' "$1"; FALHOU=$((FALHOU+1)); }
checa() { if [ "$2" = 0 ]; then ok "$1"; else falha "$1"; fi; }

# ── HOME isolado ──────────────────────────────────────────────────────────
TESTE=$(mktemp -d "${TMPDIR:-/tmp}/cli-setup-test.XXXXXX")
trap 'rm -rf "$TESTE"' EXIT
export HOME="$TESTE/home"; mkdir -p "$HOME"

# ── catálogo ──────────────────────────────────────────────────────────────
# Usa a chave real quando disponível: /v1/me é o que define o plano, e sem ele
# o filtro de modelos não roda como em produção.
CHAVE="${CLI_TEST_KEY:-ck_aaaaaaaaaaaaaaaaaaaa}"
CATALOGO_JSON=$(curl -s -m 25 "$BASE/v1/models" -H "x-api-key: $CHAVE")
case "$CATALOGO_JSON" in
  *'"data"'*) ;;
  *) echo "não consegui ler $BASE/v1/models — verifique a internet"; exit 1 ;;
esac
CATALOGO_LIDO=1
cat_plano_carregar "$CHAVE" >/dev/null 2>&1 || true
export CATALOGO_JSON CATALOGO_LIDO CAT_PLANO_IDS JSON_TOOL BASE

CAT_N=$(cat_contar); OPUS_ID=$(cat_melhor_tier opus); SONNET_ID=$(cat_melhor_tier sonnet)
HAIKU_ID=$(cat_melhor_tier haiku); PADRAO_ID=$(cat_padrao_geral)
export CHAVE OPUS_ID SONNET_ID HAIKU_ID PADRAO_ID CAT_N

export CX_DIR="$HOME/.codex" CX_CFG="$HOME/.codex/config.toml"
export CX_CATALOGO="$CX_DIR/cli-setup-models.json"
export CX_MODELO_ARQ="$CX_DIR/.cli-setup-modelo"
export CX_BK="$HOME/.config/cli-setup/codex-config.toml.anterior"
export CC_CFG="$HOME/.claude/settings.json"
export OC_CFG="$HOME/.config/opencode/opencode.json"
export OC_KEY="$HOME/.config/opencode/kodeo-api-key"

# ── funções de aplicação, extraídas do instalar.sh ────────────────────────
# O bloco começa em "APLICAR" e termina na seção principal. O número da etapa
# muda com o tempo, então casamos pelo título, sem o número.
FUN="$TESTE/fun.sh"
awk '/^# ══ [0-9]+\/[0-9]+  APLICAR/{p=1} p' "$REPO/instalar.sh" \
  | awk '/^# ══ principal/{exit} {print}' > "$FUN"
if ! grep -q 'aplicar_claude_code' "$FUN"; then
  echo "não consegui extrair as funções de aplicação de instalar.sh"; exit 1
fi
. "$FUN"

# cd_escrever monta a config pelo caminho completo (conectores, marketplaces,
# egress). A tela 4 não rodou aqui, então as variáveis dela ficam vazias e as
# funções usam fallback.
EGRESS_MODE="${EGRESS_MODE:-padrao}"; MCP_DIRS="${MCP_DIRS:-}"; MCP_REMOTOS="${MCP_REMOTOS:-}"
BUSCA_PROVEDOR="${BUSCA_PROVEDOR:-}"; BUSCA_CHAVE="${BUSCA_CHAVE:-}"
GITHUB_CLIENT_ID="${GITHUB_CLIENT_ID:-}"

passo() { local t="$1"; shift; local o; o=$("$@" 2>&1) || { printf '    (falhou: %s)\n' "$(printf '%s' "$o"|head -c 120)"; }; }
pasta_3p() { printf '%s/Library/Application Support/Claude-3p' "$HOME"; }
cx_app() { :; }
cd_reiniciar() { :; }

# Sem chave real não há plano: o filtro de modelos não se aplica, mas os testes
# de preservação e desfazer continuam valendo.
if [ -z "${CAT_PLANO_IDS:-}" ]; then
  printf '  \033[33maviso\033[0m sem CLI_TEST_KEY: testando sem o filtro do plano\n\n'
fi

printf 'modelos=%s padrão=%s opus=%s sonnet=%s haiku=%s\n\n' \
  "$CAT_N" "$PADRAO_ID" "$OPUS_ID" "${SONNET_ID:-(nenhum)}" "${HAIKU_ID:-(nenhum)}"

# ══ 1. configuração pré-existente é preservada ════════════════════════════
echo "1. Configuração pré-existente é preservada"
mkdir -p "$(dirname "$CC_CFG")" "$CX_DIR" "$HOME/.config/opencode"
cat > "$CC_CFG" <<'JSON'
{
  "permissions": { "allow": ["Bash(ls)"] },
  "env": { "MINHA_VAR": "valor-do-usuario" }
}
JSON
cat > "$CX_CFG" <<'TOML'
model = "gpt-5.5"
approval_policy = "on-request"

[profiles.rapido]
model = "gpt-5.5"
TOML
cat > "$OC_CFG" <<'JSON'
{
  "plugins": ["github:sbacaro/CLI-Startup"],
  "model": "openai/gpt-5.5"
}
JSON

aplicar_claude_code  >/dev/null 2>&1
aplicar_codex        >/dev/null 2>&1
aplicar_opencode     >/dev/null 2>&1
aplicar_claude_desktop >/dev/null 2>&1

perm=$(json_ler "$CC_CFG" permissions.allow)
[ "$perm" = '["Bash(ls)"]' ] && ok "settings.json manteve permissions do usuário" \
  || falha "settings.json perdeu permissions ($perm)"

mv=$(json_ler "$CC_CFG" env.MINHA_VAR)
[ "$mv" = "valor-do-usuario" ] && ok "settings.json manteve variável do usuário no env" \
  || falha "settings.json perdeu env do usuário"

pl=$(json_ler "$OC_CFG" plugins)
[ "$pl" = '["github:sbacaro/CLI-Startup"]' ] && ok "opencode.json manteve os plugins do usuário" \
  || falha "opencode.json perdeu plugins"

grep -qs "approval_policy" "$CX_CFG" && ok "config.toml manteve approval_policy do usuário" \
  || falha "config.toml perdeu approval_policy"
grep -qs "profiles.rapido" "$CX_CFG" && ok "config.toml manteve profiles do usuário" \
  || falha "config.toml perdeu profiles"
echo

# ══ 2. o padrão não é o MiniMax ═══════════════════════════════════════════
echo "2. Modelo padrão é o correto, não o primeiro da lista da API"
prim=$(cat_ids | head -1)
[ "$prim" = "minimax-m2.7" ] \
  && ok "a API lista minimax-m2.7 primeiro (cenário do bug)" \
  || ok "a API não lista minimax primeiro ($prim)"
[ "$PADRAO_ID" != "minimax-m2.7" ] && ok "padrão é $PADRAO_ID (não o minimax)" \
  || falha "padrão caiu no minimax"

CX_ESPERADO=$(printf '%s\n' "${CAT_PLANO_IDS:-}" | grep -E '^(gpt|codex|o[0-9])' | sort -V | tail -1)
[ -z "$CX_ESPERADO" ] && CX_ESPERADO=$(cat_ids | cut -f1 | grep -E '^(gpt|codex|o[0-9])' | head -1)
grep -q "^model = \"$CX_ESPERADO\"" "$CX_CFG" \
  && ok "config.toml fixa model = $CX_ESPERADO (OpenAI do plano)" \
  || falha "config.toml não fixa o modelo OpenAI ($CX_ESPERADO)"
grep -q "^model = \"$PADRAO_ID\"" "$CX_CFG" \
  && falha "config.toml recebeu modelo Anthropic ($PADRAO_ID)" \
  || ok "config.toml não recebeu modelo Anthropic"

if [ -f "$CX_CATALOGO" ]; then
  prim_cx=$(catalogo_chaves < /dev/null 2>/dev/null || true)
  slug0=$(JSON_TOOL="$JSON_TOOL" node -e 'const d=require(process.argv[1]);process.stdout.write(String((d.models[0]||{}).slug||""))' "$CX_CATALOGO" 2>/dev/null \
          || python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["models"][0]["slug"])' "$CX_CATALOGO" 2>/dev/null)
  [ "$slug0" = "$CX_ESPERADO" ] && ok "catálogo do Codex põe o padrão em primeiro" \
    || falha "catálogo do Codex com primeiro=$slug0, esperado=$CX_ESPERADO"
  nao_openai=$(node -e 'const d=require(process.argv[1]);process.stdout.write(d.models.filter(m=>!/^(gpt|codex|o[0-9])/i.test(m.slug)).map(m=>m.slug).join(","))' "$CX_CATALOGO" 2>/dev/null)
  [ -z "$nao_openai" ] && ok "catálogo do Codex só tem modelos OpenAI" \
    || falha "catálogo do Codex tem modelos de outra família: $nao_openai"
else
  falha "catálogo do Codex não foi gravado"
fi
echo

# ══ 3. tier ausente não vira outro provedor ═══════════════════════════════
echo "3. Tier ausente não vira outro provedor"
if [ -z "$SONNET_ID" ]; then
  grep -qs "ANTHROPIC_DEFAULT_SONNET_MODEL" "$CC_CFG" \
    && falha "criou SONNET apontando para algo" \
    || ok "nenhum SONNET inventado (plano não tem Sonnet)"
  grep -qs "ANTHROPIC_DEFAULT_SONNET_MODEL" "$HOME/.zshrc" 2>/dev/null \
    && falha "SONNET no .zshrc" || ok ".zshrc sem SONNET inventado"
else
  ok "o plano tem Sonnet: $SONNET_ID (nada a testar aqui)"
fi
grep -qs "grok-4.7" "$CC_CFG" && falha "Sonnet foi redirecionado para grok (bug antigo)" \
  || ok "Sonnet não foi redirecionado para grok"
echo

# ══ 4. idempotência ═══════════════════════════════════════════════════════
echo "4. Rodar duas vezes não duplica"
antes=$(grep -c ">>> kodeo >>>" "$HOME/.zshrc" 2>/dev/null || echo 0)
aplicar_claude_code >/dev/null 2>&1
depois=$(grep -c ">>> kodeo >>>" "$HOME/.zshrc" 2>/dev/null || echo 0)
[ "$antes" = "$depois" ] && ok "bloco do shell não duplicou ($depois)" \
  || falha "blocos duplicaram: $antes → $depois"

n1=$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["providers"]["kodeo"]["models"]))' "$OC_CFG" 2>/dev/null || echo "?")
aplicar_opencode >/dev/null 2>&1
n2=$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["providers"]["kodeo"]["models"]))' "$OC_CFG" 2>/dev/null || echo "?")
[ "$n1" = "$n2" ] && ok "provedor do OpenCode estável ($n2 modelos)" \
  || falha "provedor mudou: $n1 → $n2"

aplicar_codex >/dev/null 2>&1
n=$(grep -c "model_providers.kodeo" "$CX_CFG" 2>/dev/null || echo 0)
[ "$n" = 1 ] && ok "provedor do Codex aparece uma vez" || falha "provedor do Codex duplicado ($n)"
echo

# ══ 4b. OpenCode no formato V2 ════════════════════════════════════════════
echo "4b. OpenCode gravado no formato do V2 (v2.x)"
python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
assert "providers" in d, "sem providers"
assert "provider" not in d, "gravou o formato V1 (provider)"
p=d["providers"]["kodeo"]
assert p.get("package")=="@opencode/ai/providers/openai-compatible", p.get("package")
assert p.get("settings",{}).get("baseURL","").endswith("/v1"), p.get("settings")
assert "npm" not in p and "options" not in p, "campos do V1 presentes"
' "$OC_CFG" 2>/dev/null \
  && ok "usa providers (V2), não provider (V1)" || falha "gravou no formato V1"

python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
ms=d["providers"]["kodeo"]["models"]
m=next(iter(ms.values()))
assert "modelID" in m and "capabilities" in m, list(m.keys())
assert m["capabilities"].get("tools") is True
' "$OC_CFG" 2>/dev/null \
  && ok "modelos têm modelID e capabilities (V2)" || falha "modelos fora do formato V2"

grep -qs '"plugins"' "$OC_CFG" && ok "plugins do usuário preservados" || falha "plugins do usuário perdidos"
echo

# ══ 4c. Claude Desktop ════════════════════════════════════════════════════
CD_CFG=$(ls "$HOME/Library/Application Support/Claude-3p/configLibrary/"*.json 2>/dev/null | grep -v _meta | head -1)
if [ -n "$CD_CFG" ]; then
  python3 -c '
import json,sys
d=json.load(open(sys.argv[1])); padrao=sys.argv[2]
ms=d["inferenceModels"]
def ck(cond, msg):
    if not cond:
        print("    -> " + msg, file=sys.stderr); sys.exit(1)
ck(d["modelDiscoveryEnabled"] is False, "discovery ligado")
ck(bool(d["inferenceGatewayApiKey"]), "sem chave")
ck(d["inferenceGatewayAuthScheme"]=="x-api-key", "auth=" + str(d.get("inferenceGatewayAuthScheme")))
ck(ms[0]["name"]==padrao, "primeiro=" + ms[0]["name"] + " padrao=" + padrao)
ck(bool(ms[0].get("anthropicFamilyTier")), "padrao sem tier")
ck(ms[0].get("isFamilyDefault") is True, "padrao nao e default do tier")
# chaves que nao existem na doc: o app descarta em silencio
ck("codeTabEnabled" not in d, "chave inventada codeTabEnabled")
ck("pluginMarketplaces" not in d, "chave inventada pluginMarketplaces")
' "$CD_CFG" "$PADRAO_ID" \
    && ok "Claude Desktop: padrão, auth e chaves coerentes" \
    || falha "Claude Desktop: config incoerente (veja $CD_CFG)"
else
  falha "Claude Desktop: nenhum config gravado"
fi
echo

# ══ 4d. config.toml com plugins do app sobrevive ao desfazer ══════════════
# Este é o defeito mais caro que a suíte pegou. Em TOML, tudo que vem depois de
# um cabeçalho de tabela pertence a ele — inclusive o que o próprio app escreve.
# Quando o provedor era delimitado por marcas no fim do arquivo, o app inseria
# notify, [plugins.*] e [mcp_servers.*] DENTRO do trecho marcado, e o desfazer
# apagava tudo junto (49 linhas numa config real).
echo "4d. config.toml preserva o que o app escreveu"
cat > "$CX_CFG" <<'TOML'
[model_providers.kodeo]
name = "Kodeo"
base_url = "https://api.kodeo.com.br/v1"
wire_api = "responses"
env_key = "KODEO_API_KEY"

notify = ["/caminho/do/app", "turn-ended"]
model_reasoning_effort = "xhigh"

[marketplaces.openai-bundled]
source_type = "local"

[plugins."browser@openai-bundled"]
enabled = true

[mcp_servers.node_repl]
command = "/caminho/node_repl"
CODEX_CLI_PATH = "/caminho/codex"
TOML
cp "$CX_CFG" "$TESTE/cfg-app.toml"
# O backup de um teste anterior faria cx_remover restaurar em vez de remover;
# aqui interessa justamente o caminho de remoção.
rm -f "$CX_BK"
# Escreve o nosso por cima. cx_escrever faz backup do arquivo ANTES de mexer
# (é o que permite restaurar depois), então o backup guardaria uma cópia já com
# a nossa tabela. Aqui o caminho exercitado é a remoção cirúrgica, não a
# restauração: o backup sai do caminho.
cx_escrever >/dev/null 2>&1
rm -f "$CX_BK"
cx_remover >/dev/null 2>&1
restou=$(cat "$CX_CFG" 2>/dev/null)
case "$restou" in
  *CODEX_CLI_PATH*) ok "CODEX_CLI_PATH do app sobreviveu" ;;
  *) falha "CODEX_CLI_PATH do app foi apagado" ;;
esac
case "$restou" in
  *'[plugins."browser@openai-bundled"]'*) ok "plugins do app sobreviveram" ;;
  *) falha "plugins do app foram apagados" ;;
esac
# notify está DEPOIS do cabeçalho da tabela, então pertence ao provedor em
# TOML: some junto, e isso é correto. O app o reescreve ao abrir.
case "$restou" in
  *notify*) ok "notify preservado (ficou fora da tabela)" ;;
  *) ok "notify saiu junto com a tabela (correto em TOML)" ;;
esac
grep -qs 'model_providers\.kodeo' "$CX_CFG" && falha "nosso provedor ficou" \
  || ok "nosso provedor saiu"
grep -qs '^# >>> kodeo >>>' "$CX_CFG" && falha "nosso bloco do topo ficou" \
  || ok "nosso bloco do topo saiu"
# Devolve o cenário que o resto da suíte espera: o config.toml do usuário
# (com approval_policy e profiles) e sem nada nosso.
cat > "$CX_CFG" <<'TOML'
model = "gpt-5.5"
approval_policy = "on-request"

[profiles.rapido]
model = "gpt-5.5"
TOML
rm -f "$CX_BK"
echo

# ══ 5. desfazer devolve o que era do usuário ══════════════════════════════
echo "5. Desfazer devolve o que era do usuário"
remover_opencode >/dev/null 2>&1
m=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("model",""))' "$OC_CFG" 2>/dev/null)
[ "$m" = "openai/gpt-5.5" ] && ok "OpenCode voltou ao modelo anterior ($m)" \
  || falha "modelo do OpenCode não voltou: '$m'"
[ -f "$OC_KEY" ] && falha "arquivo da chave ficou para trás" || ok "arquivo da chave removido"

remover_codex >/dev/null 2>&1
grep -qs "model_providers.kodeo" "$CX_CFG" && falha "provedor do Codex ficou" \
  || ok "provedor do Codex saiu"
grep -qs "approval_policy" "$CX_CFG" && ok "config.toml original voltou" \
  || falha "config.toml original não voltou"
[ -f "$CX_CATALOGO" ] && falha "catálogo do Codex ficou" || ok "catálogo do Codex removido"
echo

# ══ resumo ════════════════════════════════════════════════════════════════
printf 'falhas: %s\n' "$FALHOU"
if [ "$FALHOU" = 0 ]; then printf '\033[32mTUDO OK\033[0m\n'; else printf '\033[31m%s falha(s)\033[0m\n' "$FALHOU"; fi
[ "$FALHOU" = 0 ]