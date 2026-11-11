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

# ══ 3c. Perfil de configuração gerenciada ════════════════════════════════
# O canal oficial é /Library/Managed Preferences e exige root, então o teste
# valida o que é verificável sem privilégio: o documento gerado respeita os
# tipos que o template da Anthropic declara. As chaves compostas vão como JSON
# em texto (type=string no template); gravá-las como array quebra o contrato.
echo "3c. Perfil gerenciado respeita os tipos do template"
_plist="$TESTE/kodeo.plist"
export JSON_TOOL
bash -c '
  . "$1/lib/json.sh"; . "$1/lib/catalogo.sh"; . "$1/lib/geradores.sh"; . "$1/lib/desktop.sh"
  export CATALOGO_JSON="{\"data\":[{\"id\":\"claude-opus-5.5\",\"display_name\":\"Opus 5.5\",\"context_length\":1000000}]}"
  mk=$(desktop_marketplaces_json 1 1); ml=$(desktop_mcp_local "")
  cd_config_json_completo() { printf "%s" "$CATALOGO_JSON" | CAT_BASE="https://x" CAT_CHAVE="ck_t" CAT_OPUS="claude-opus-5.5" CAT_MARKETPLACES="$mk" CAT_MCP_LOCAL="$ml" catalogo_gerar_claude; }
  desktop_plist_gerar
' _ "$REPO" >"$_plist" 2>/dev/null

if plutil -lint "$_plist" >/dev/null 2>&1; then
  ok "perfil é um plist válido"
  _res=$(python3 - "$_plist" <<'PY'
import plistlib,sys
d=plistlib.load(open(sys.argv[1],"rb"))
f=[]
# o template declara type=string para as compostas
for k in ("inferenceModels","allowedPluginMarketplaces","coworkEgressAllowedHosts"):
    if k in d and not isinstance(d[k],str): f.append(f"{k} não é string (template exige)")
# as booleanas do template
for k in ("skillScanningEnabled","projectsEnabled","builtinBrowserEnabled"):
    if k in d and not isinstance(d[k],bool): f.append(f"{k} não é boolean")
# desktopHome substitui as chaves depreciadas de aba
if d.get("desktopHome")!="standard": f.append("desktopHome != standard")
for k in ("chatTabEnabled","coworkTabEnabled"):
    if k in d: f.append(f"{k} ainda presente (depreciada)")
if not d.get("inferenceGatewayBaseUrl"): f.append("sem baseUrl")
if "PayloadType" not in d: f.append("sem PayloadType")
print("OK" if not f else "FALHA: "+"; ".join(f))
PY
)
  case "$_res" in
    OK) ok "tipos conferem: compostas em texto, booleanas em bool, desktopHome" ;;
    *) falha "$_res" ;;
  esac
else
  falha "perfil gerado não é um plist válido"
fi
echo

# ══ 3b. MCP local não depende de pasta ════════════════════════════════════
# A tela prometia "Sem pastas, só Memory e Sequential Thinking entram" e a
# função devolvia [] antes de chegar neles: quem só dava Enter ficava sem MCP
# nenhum. Os três pacotes precisam estar no cache do npm, senão a checagem vira
# um "tudo bem, nada entrou" e não prova nada.
echo "3b. MCP local entra mesmo sem pastas do Filesystem"
_ml_vazio=$(desktop_mcp_local "" 2>/dev/null)
_python_mcp='
import json,sys
nomes=[m.get("name") for m in json.load(sys.stdin)]
falta=[n for n in ("Memory","Sequential Thinking") if n not in nomes]
print("FALTA:"+",".join(falta) if falta else "OK:"+",".join(nomes))
'
_res=$(printf '%s' "$_ml_vazio" | python3 -c "$_python_mcp" 2>/dev/null || echo "ERRO")
case "$_res" in
  OK:*) ok "sem pastas entram ${_res#OK:}" ;;
  FALTA:*) falha "sem pastas faltou ${_res#FALTA:} (bug do return antecipado)" ;;
  *) falha "JSON inválido do MCP local: ${_ml_vazio:0:60}" ;;
esac

# Com pasta, o Filesystem entra e recebe a pasta nos args.
_ml_dir=$(desktop_mcp_local "$TESTE/docs" 2>/dev/null)
_res=$(printf '%s' "$_ml_dir" | python3 -c '
import json,sys
ms=json.load(sys.stdin); alvo=sys.argv[1]
fs=[m for m in ms if m.get("name")=="Filesystem"]
if not fs: print("FALTA:Filesystem")
elif alvo not in (fs[0].get("args") or []): print("FALTA:pasta nos args")
else: print("OK")
' "$TESTE/docs" 2>/dev/null || echo "ERRO")
case "$_res" in
  OK) ok "com pasta o Filesystem entra e recebe a pasta" ;;
  FALTA:*) falha "com pasta: ${_res#FALTA:}" ;;
  *) falha "JSON inválido com pasta" ;;
esac
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

# ══ 4a2. Plugins do Desktop ═══════════════════════════════════════════════
# Declarar o marketplace só o clona. O plugin só aparece quando existe registro
# em installed_plugins.json e a chave ligada em cowork_settings.json — nada no
# app escreve isso por fora da interface. O sintoma de antes era exatamente
# "0 enabled local plugins (0 installed)" com os dois marketplaces sincronizados.
echo "4a2. Plugins do Desktop têm registro de instalação"

# o marketplace precisa apontar para o diretório oficial, não para o do produto
_repo=$(desktop_marketplaces_json 1 1 | python3 -c '
import json,sys
for e in json.load(sys.stdin):
    if e.get("expectedName")=="claude-plugins-official": print(e.get("repo"))
' 2>/dev/null)
[ "$_repo" = "anthropics/claude-plugins-official" ] \
  && ok "marketplace de plugins é o oficial ($_repo)" \
  || falha "marketplace de plugins aponta para '$_repo' (anthropics/claude-code não tem plugin instalável)"

# monta um perfil 3P falso com marketplace clonado e roda a instalação
# O nome do marketplace é o real: o desfazer casa por ele, e um nome inventado
# faria o teste "provar" que a remoção falha quando na verdade ela só está
# recusando um marketplace que não é nosso.
_fake="$TESTE/claude3p/local-agent-mode-sessions/acc/org"
mkdir -p "$_fake/cowork_plugins/marketplaces/claude-plugins-official/.claude-plugin"
cat >"$_fake/cowork_plugins/marketplaces/claude-plugins-official/.claude-plugin/marketplace.json" <<'JSON'
{ "name": "claude-plugins-official", "plugins": [
  { "name": "code-review", "source": "./plugins/code-review" },
  { "name": "commit-commands", "source": "./plugins/commit-commands" },
  { "name": "remoto", "source": { "source": "git-subdir", "url": "https://x" } }
] }
JSON
DESKTOP_PLUGINS="code-review commit-commands remoto"
pasta_3p() { printf '%s' "$TESTE/claude3p"; }
cp "$REPO/lib/desktop.sh" "$TESTE/desktop_teste.sh"
( . "$TESTE/desktop_teste.sh"; cd_plugins ) >"$TESTE/plugin_out" 2>&1

_preg="$_fake/cowork_plugins/installed_plugins.json"
_pcfg="$_fake/cowork_settings.json"
if [ -f "$_preg" ]; then
  ok "installed_plugins.json foi escrito"
  _res=$(python3 - "$_preg" "$_pcfg" <<'PY'
import json,sys
reg=json.load(open(sys.argv[1])); cfg=json.load(open(sys.argv[2]))
p=reg.get("plugins") or {}; e=cfg.get("enabledPlugins") or {}
nomes={k.split("@")[0] for k in p}
f=[]
if "code-review" not in nomes: f.append("code-review fora")
if "commit-commands" not in nomes: f.append("commit-commands fora")
if "remoto" in nomes: f.append("plugin remoto (source objeto) foi incluído")
for k in p:
    if "@" not in k: f.append(f"id sem @marketplace: {k}")
    if p[k][0].get("scope")!="user": f.append(f"scope errado em {k}")
    if e.get(k) is not True: f.append(f"{k} não está ligado")
print("OK" if not f else "FALHA: "+"; ".join(f))
PY
)
  case "$_res" in
    OK) ok "registro correto: scope user, ligado, sem remoto" ;;
    *) falha "$_res" ;;
  esac

  # desfazer remove só o nosso
  ( . "$TESTE/desktop_teste.sh"; cd_plugins_remover ) >/dev/null 2>&1
  _rest=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))['plugins']))" "$_preg" 2>/dev/null || echo "?")
  [ "$_rest" = "0" ] && ok "desfazer remove os plugins instalados" \
    || falha "desfazer deixou $_rest plugin(s)"
else
  falha "installed_plugins.json não foi escrito"
fi
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

# ══ 4e. catálogo do Codex é válido e não mente sobre a identidade ═════════
# Duas armadilhas, ambas silenciosas:
#   1. O catálogo não é lista de nomes: o app valida cada modelo e recusa o
#      ARQUIVO INTEIRO se faltar campo ("missing field supported_reasoning_levels").
#      Gravar só {slug,display_name,context} deixava o Codex sem catálogo.
#   2. O /v1/codex/modelos serve base_instructions dizendo que o modelo é o
#      "Codex CLI, open source project led by OpenAI". Como o arquivo é local e
#      o app o lê a cada execução, substituir esse texto muda a identidade.
echo "4e. catálogo do Codex é válido e não diz que é da OpenAI"
if [ -f "$CX_CATALOGO" ]; then
  campos=$(node -e 'const d=require(process.argv[1]);process.stdout.write(String(Object.keys(d.models[0]||{}).length))' "$CX_CATALOGO" 2>/dev/null)
  [ "${campos:-0}" -gt 20 ] && ok "modelos têm $campos campos (schema completo)" \
    || falha "modelo com só $campos campos: o app recusa o arquivo"
  tem_srl=$(node -e 'const d=require(process.argv[1]);process.stdout.write(String("supported_reasoning_levels" in (d.models[0]||{})))' "$CX_CATALOGO" 2>/dev/null)
  [ "$tem_srl" = "true" ] && ok "tem supported_reasoning_levels (obrigatório)" \
    || falha "falta supported_reasoning_levels: o app recusa o catálogo"
  bi=$(node -e 'const d=require(process.argv[1]);process.stdout.write(String((d.models[0]||{}).base_instructions||""))' "$CX_CATALOGO" 2>/dev/null)
  case "$bi" in
    *"led by OpenAI"*) falha "base_instructions ainda diz que é projeto da OpenAI" ;;
    *Kodeo*) ok "base_instructions aponta o gateway, não a OpenAI" ;;
    "") ok "base_instructions removido (o app usa o padrão)" ;;
    *) ok "base_instructions substituído" ;;
  esac
else
  falha "catálogo do Codex não foi gravado"
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