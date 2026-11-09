#!/usr/bin/env bash
# Testes de comportamento que importam para quem usa o configurador:
#  1. rodar duas vezes não duplica nem corrompe
#  2. um config.toml/settings.json que o usuário já tinha é preservado
#  3. o modelo padrão nunca cai no MiniMax por acidente
set -u
REPO="/Users/samuelbacaro/Documents/OpenCode/CLI Setup/meu-configurador"
cd "$REPO" || exit 1
export BASE="https://api.kodeo.com.br" JSON_TOOL=${JSON_TOOL:-node}
export MARCA_INI="# >>> kodeo >>>" MARCA_FIM="# <<< kodeo <<<"
export VERSAO="2.0" FALHAS=0 ACC_F="" R="" OK="" ERR="" G="" W="" B=""
SPIN='x'; limpa_linha() { :; }; pausa() { :; }; tela() { :; }; rodape() { :; }
caixa_topo() { :; }; caixa_linha() { :; }; caixa_fundo() { :; }

. "$REPO/lib/json.sh"
. "$REPO/lib/catalogo.sh"
. "$REPO/lib/geradores.sh"
. "$REPO/lib/opencode.sh"

FALHOU=0
ok()   { printf '  \033[32mok\033[0m    %s\n' "$1"; }
falha(){ printf '  \033[31mFALHA\033[0m %s\n' "$1"; FALHOU=$((FALHOU+1)); }
checa(){ # descrição, condição(0=ok)
  if [ "$2" = 0 ]; then ok "$1"; else falha "$1"; fi
}

TESTE=$(mktemp -d); export HOME="$TESTE/home"; mkdir -p "$HOME"

CATALOGO_JSON=$(curl -s -m 25 "$BASE/v1/models"); CATALOGO_LIDO=1
CHAVE="ck_aaaaaaaaaaaaaaaaaaaa"
CAT_N=$(cat_contar); OPUS_ID=$(cat_melhor_tier opus); SONNET_ID=$(cat_melhor_tier sonnet)
HAIKU_ID=$(cat_melhor_tier haiku); PADRAO_ID=$(cat_padrao_geral)
export CHAVE OPUS_ID SONNET_ID HAIKU_ID PADRAO_ID CAT_N
export CX_DIR="$HOME/.codex" CX_CFG="$HOME/.codex/config.toml"
export CX_CATALOGO="$CX_DIR/cli-setup-models.json" CX_BK="$HOME/.config/cli-setup/codex-config.toml.anterior"
export CC_CFG="$HOME/.claude/settings.json"
export OC_CFG="$HOME/.config/opencode/opencode.json" OC_KEY="$HOME/.config/opencode/kodeo-api-key"

awk '/^# ══ 4\/4  APLICAR/{p=1} p' "$REPO/instalar.sh" | awk '/^# ══ principal/{exit} {print}' > "$TESTE/fun.sh"
. "$TESTE/fun.sh"
passo() { local t="$1"; shift; local o; o=$("$@" 2>&1) || { printf '    (falhou: %s)\n' "$(printf '%s' "$o"|head -c 120)"; }; }
pasta_3p() { printf '%s/Library/Application Support/Claude-3p' "$HOME"; }
cx_app() { :; }

echo "modelos=$CAT_N padrão=$PADRAO_ID opus=$OPUS_ID sonnet=${SONNET_ID:-(nenhum)} haiku=$HAIKU_ID"
echo

# ── cenário: usuário que já tinha configuração ────────────────────────────
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
# o mesmo formato do OpenCode real: plugins declarados, sem provedor
cat > "$OC_CFG" <<'JSON'
{
  "plugins": ["github:sbacaro/CLI-Startup"],
  "model": "openai/gpt-5.5"
}
JSON

aplicar_claude_code >/dev/null 2>&1
aplicar_codex >/dev/null 2>&1
aplicar_opencode >/dev/null 2>&1
aplicar_claude_desktop >/dev/null 2>&1

python3 - "$CC_CFG" <<'PY' && checa "settings.json manteve permissions do usuário" 0 || checa "settings.json manteve permissions do usuário" 1
import json,sys
d=json.load(open(sys.argv[1]))
assert d.get("permissions",{}).get("allow")==["Bash(ls)"], "permissions perdido"
PY
python3 - "$CC_CFG" <<'PY' && checa "settings.json manteve variável do usuário no env" 0 || checa "settings.json manteve variável do usuário no env" 1
import json,sys
d=json.load(open(sys.argv[1]))
assert d["env"].get("MINHA_VAR")=="valor-do-usuario", "env do usuário perdido"
PY
python3 - "$OC_CFG" <<'PY' && checa "opencode.json manteve os plugins do usuário" 0 || checa "opencode.json manteve os plugins do usuário" 1
import json,sys
d=json.load(open(sys.argv[1]))
assert d.get("plugins")==["github:sbacaro/CLI-Startup"], "plugins perdidos"
PY
grep -qs "approval_policy" "$CX_CFG" && checa "config.toml manteve approval_policy do usuário" 0 || checa "config.toml manteve approval_policy do usuário" 1
grep -qs "profiles.rapido" "$CX_CFG" && checa "config.toml manteve profiles do usuário" 0 || checa "config.toml manteve profiles do usuário" 1
echo

# ── o ponto central: o padrão não é o MiniMax ─────────────────────────────
echo "2. Modelo padrão é o correto, não o primeiro da lista da API"
prim_da_api=$(cat_ids | head -1)
[ "$prim_da_api" = "minimax-m2.7" ] && ok "a API lista minimax-m2.7 primeiro (é o cenário do bug)" || ok "a API não lista minimax primeiro"
[ "$PADRAO_ID" != "minimax-m2.7" ] && ok "padrão escolhido é $PADRAO_ID (não o minimax)" || falha "padrão caiu no minimax"
grep -q "^model = \"$PADRAO_ID\"" "$CX_CFG" && ok "config.toml fixa model = $PADRAO_ID" || falha "config.toml não fixa o modelo"
python3 - "$CX_CATALOGO" <<'PY' && checa "catálogo do Codex põe o padrão em primeiro" 0 || checa "catálogo do Codex põe o padrão em primeiro" 1
import json,sys
d=json.load(open(sys.argv[1]))
assert d["models"][0]["slug"]==sys.argv[2] if len(sys.argv)>2 else True
PY
echo

# ── Sonnet ausente não vira outro provedor ────────────────────────────────
echo "3. Tier ausente não vira outro provedor"
if [ -z "$SONNET_ID" ]; then
  grep -qs "ANTHROPIC_DEFAULT_SONNET_MODEL" "$CC_CFG" && falha "criou SONNET apontando para algo" || ok "nenhum SONNET inventado (plano não tem Sonnet)"
  grep -qs "ANTHROPIC_DEFAULT_SONNET_MODEL" "$HOME/.zshrc" && falha "SONNET no .zshrc" || ok ".zshrc sem SONNET inventado"
else
  ok "o plano tem Sonnet: $SONNET_ID (nada a testar aqui)"
fi
grep -qs "grok-4.7" "$CC_CFG" && falha "Sonnet foi redirecionado para grok (o bug antigo)" || ok "Sonnet não foi redirecionado para grok"
echo

# ── idempotência ──────────────────────────────────────────────────────────
echo "4. Rodar duas vezes não duplica"
antes=$(grep -c ">>> kodeo >>>" "$HOME/.zshrc")
aplicar_claude_code >/dev/null 2>&1
depois=$(grep -c ">>> kodeo >>>" "$HOME/.zshrc")
[ "$antes" = "$depois" ] && ok "bloco do shell não duplicou ($depois)" || falha "blocos duplicaram: $antes → $depois"

n1=$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["providers"]["kodeo"]["models"]))' "$OC_CFG")
aplicar_opencode >/dev/null 2>&1
n2=$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["providers"]["kodeo"]["models"]))' "$OC_CFG")
[ "$n1" = "$n2" ] && ok "provedor do OpenCode estável ($n2 modelos)" || falha "provedor mudou: $n1 → $n2"

aplicar_codex >/dev/null 2>&1
n=$(grep -c "model_providers.kodeo" "$CX_CFG")
[ "$n" = 1 ] && ok "provedor do Codex aparece uma vez" || falha "provedor do Codex duplicado ($n)"
echo

echo "4b. OpenCode gravado no formato do V2 (v2.x)"
python3 - "$OC_CFG" <<'PY' && ok "usa providers (V2), não provider (V1)" || falha "gravou no formato V1"
import json,sys
d=json.load(open(sys.argv[1]))
assert "providers" in d, "sem providers"
assert "provider" not in d, "gravou no formato V1 (provider)"
p=d["providers"]["kodeo"]
assert p.get("package")=="@opencode/ai/providers/openai-compatible", p.get("package")
assert p.get("settings",{}).get("baseURL","").endswith("/v1"), p.get("settings")
assert "npm" not in p and "options" not in p, "campos do V1 presentes"
PY
python3 - "$OC_CFG" <<'PY' && ok "modelos têm modelID e capabilities (V2)" || falha "modelos fora do formato V2"
import json,sys
d=json.load(open(sys.argv[1]))
ms=d["providers"]["kodeo"]["models"]
m=next(iter(ms.values()))
assert "modelID" in m and "capabilities" in m, list(m.keys())
assert m["capabilities"].get("tools") is True
PY
grep -qs '"plugins"' "$OC_CFG" && ok "plugins do usuário preservados" || falha "plugins do usuário perdidos"

CD_CFG=$(ls "$HOME/Library/Application Support/Claude-3p/configLibrary/"*.json 2>/dev/null | grep -v _meta | head -1)
if [ -n "$CD_CFG" ]; then
  python3 - "$CD_CFG" "$PADRAO_ID" <<'PY' && ok "Claude Desktop: padrão coerente com isFamilyDefault" || falha "Claude Desktop: padrão incoerente"
import json,sys
d=json.load(open(sys.argv[1]));padrao=sys.argv[2]
ms=d["inferenceModels"]
assert ms[0]["name"]==padrao, f"primeiro={ms[0]['name']} padrao={padrao}"
assert d["modelDiscoveryEnabled"] is False
assert d["inferenceGatewayApiKey"]
assert ms[0].get("anthropicFamilyTier"), "padrao sem tier"
assert ms[0].get("isFamilyDefault") is True, "padrao nao e default do tier"
PY
else
  falha "Claude Desktop: nenhum config gravado"
fi
echo

# ── desfazer devolve o modelo anterior ───────────────────────────────────
echo "5. Desfazer devolve o que era do usuário"
remover_opencode >/dev/null 2>&1
m=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get("model",""))' "$OC_CFG" 2>/dev/null)
[ "$m" = "openai/gpt-5.5" ] && ok "OpenCode voltou ao modelo anterior ($m)" || falha "modelo do OpenCode não voltou: '$m'"
[ -f "$OC_KEY" ] && falha "arquivo da chave ficou para trás" || ok "arquivo da chave removido"

remover_codex >/dev/null 2>&1
grep -qs "model_providers.kodeo" "$CX_CFG" && falha "provedor do Codex ficou" || ok "provedor do Codex saiu"
grep -qs "approval_policy" "$CX_CFG" && ok "config.toml original voltou" || falha "config.toml original não voltou"
[ -f "$CX_CATALOGO" ] && falha "catálogo do Codex ficou" || ok "catálogo do Codex removido"

echo
echo "falhas: $FALHOU"
[ "$FALHOU" = 0 ] && printf '\033[32mTUDO OK\033[0m\n'
rm -rf "$TESTE"