#!/usr/bin/env bash
# lib/catalogo.sh — lê o catálogo de modelos do plano na API e responde perguntas sobre ele.
#
# A ideia central: nada de lista de modelos fixa no script. A API já sabe quais modelos
# o plano tem, o contexto de cada um e as capacidades. O configurador pergunta, e cada
# ferramenta recebe a lista que ela espera — inclusive o modelo certo como padrão.
#
# Requer: curl. Usa node ou python3 para ler o JSON.

CATALOGO_JSON=""
CATALOGO_LIDO=0

# familias: qual família cada modelo é, pelo id. A ordem importa: "claude-opus-5-kodeo"
# contém "claude" e "opus"; "kodeo-opus-5" não contém "claude" mas é Opus.
cat_familia() { # id → anthropic | openai | xai | zhipu | deepseek | minimax | outro
  local i="$1"
  case "$i" in
    *claude*|*opus*|*fable*|*sonnet*|*haiku*) printf 'anthropic' ;;
    *gpt*|*codex*)                            printf 'openai' ;;
    *grok*)                                   printf 'xai' ;;
    *glm*)                                    printf 'zhipu' ;;
    *deepseek*)                               printf 'deepseek' ;;
    *minimax*)                                printf 'minimax' ;;
    *)                                        printf 'outro' ;;
  esac
}

# tier de um modelo Claude: opus | sonnet | haiku | fable | (vazio)
cat_tier() { # id → tier
  local i="$1"
  case "$i" in
    *opus*)   printf 'opus' ;;
    *sonnet*) printf 'sonnet' ;;
    *haiku*)  printf 'haiku' ;;
    *fable*)  printf 'fable' ;;
    *)        printf '' ;;
  esac
}

# catalogo_carregar CHAVE → 0 se conseguiu (grava CATALOGO_JSON)
catalogo_carregar() {
  local chave="$1"
  [ "$CATALOGO_LIDO" -eq 1 ] && return 0
  CATALOGO_JSON=$(curl -s -m 25 -A "cli-setup/1.0" "$BASE/v1/models" -H "x-api-key: $chave" 2>/dev/null)
  case "$CATALOGO_JSON" in *'"data"'*) CATALOGO_LIDO=1; return 0;; esac
  CATALOGO_JSON=""; return 1
}

# ── Modelos que o plano realmente pode usar ────────────────────────────────
# /v1/models lista TODOS os modelos do catálogo (22), inclusive os de planos
# superiores: um deles responde 403 "está no Kodeo Ultra". A lista que vale é
# a do /v1/me, campo "modelos". Sem esse filtro o configurador grava modelos
# que o usuário não consegue chamar.
cat_plano_carregar() { # CHAVE → 0 e grava CAT_PLANO_IDS (um id por linha)
  local chave="$1" json
  [ -n "${CAT_PLANO_IDS:-}" ] && return 0
  json=$(curl -s -m 20 -A "cli-setup/1.0" "$BASE/v1/me" -H "x-api-key: $chave" 2>/dev/null)
  CAT_PLANO_JSON="$json"
  CAT_PLANO_IDS=""
  case "$json" in *'"modelos"'*) ;; *) return 1;; esac
  CAT_PLANO_IDS=$(printf '%s' "$json" | cat_extrair_modelos)
  [ -n "$CAT_PLANO_IDS" ]
}

# cat_extrair_modelos — lê o JSON do /v1/me no stdin e imprime um id por linha
cat_extrair_modelos() {
  if [ "${JSON_TOOL:-}" = node ]; then
    node -e 'let t="";process.stdin.on("data",c=>t+=c).on("end",()=>{let d={};try{d=JSON.parse(t)}catch{process.exit(0)};const ms=Array.isArray(d.modelos)?d.modelos:[];process.stdout.write(ms.join("\n"))});'
  else
    python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: raise SystemExit(0)
ms=d.get("modelos") if isinstance(d.get("modelos"),list) else []
sys.stdout.write("\n".join(str(m) for m in ms))'
  fi
}

# cat_no_plano ID → 0 se o plano inclui esse modelo (vazio = não filtrar)
cat_no_plano() {
  local id="$1"
  [ -z "${CAT_PLANO_IDS:-}" ] && return 0
  printf '%s\n' "$CAT_PLANO_IDS" | grep -Fxq "$id"
}

# cat_ids → um id por linha, na ordem da API
cat_ids() { cat_campo id; }

# cat_campo CAMPO → "id<TAB>valor" por linha
cat_campo() {
  local campo="$1"
  printf '%s' "$CATALOGO_JSON" | catalogo_json "$campo"
}

# catalogo_json — lê o JSON do stdin e imprime linhas "id<TAB>campo"
catalogo_json() {
  local campo="$1"
  if [ "${JSON_TOOL:-}" = node ]; then
    node -e '
const campo=process.argv[1];
let t="";process.stdin.on("data",c=>t+=c).on("end",()=>{
  let d={};try{d=JSON.parse(t)}catch{process.exit(0)}
  const ms=Array.isArray(d.data)?d.data:(Array.isArray(d.models)?d.models:[]);
  for(const m of ms){
    let v;
    if(campo==="id")v=m.id||m.slug;
    else if(campo==="nome")v=m.display_name||m.name||m.id||m.slug;
    else if(campo==="contexto")v=m.context_length||m.context_window||m.max_input_tokens||0;
    else if(campo==="saida")v=m.max_tokens||0;
    else v=m[campo];
    if(v===undefined||v===null)v="";
    process.stdout.write((m.id||m.slug)+"\t"+v+"\n");
  }
});' "$campo"
  else
    python3 -c '
import sys,json
campo=sys.argv[1]
try: d=json.load(sys.stdin)
except Exception: raise SystemExit(0)
ms=d.get("data") if isinstance(d.get("data"),list) else (d.get("models") if isinstance(d.get("models"),list) else [])
for m in ms:
    i=m.get("id") or m.get("slug") or ""
    if campo=="id": v=i
    elif campo=="nome": v=m.get("display_name") or m.get("name") or i
    elif campo=="contexto": v=m.get("context_length") or m.get("context_window") or m.get("max_input_tokens") or 0
    elif campo=="saida": v=m.get("max_tokens") or 0
    else: v=m.get(campo)
    if v is None: v=""
    print(f"{i}\t{v}")
' "$campo"
  fi
}

# cat_melhor_tier TIER → o id mais adequado para aquele tier
# Critério, nesta ordem:
#   1. id canônico (sem sufixo de revenda "-kodeo")
#   2. família canônica (claude-* antes de kodeo-*)
#   3. maior versão no nome (opus-5.5 vence opus-5)
#   4. maior contexto
# O número da versão vem antes do contexto porque duas versões do mesmo modelo
# têm o mesmo contexto: desempatar pelo contexto deixaria a escolha ao acaso.
cat_melhor_tier() {
  local tier="$1"
  printf '%s' "$CATALOGO_JSON" | catalogo_escolher "$tier"
}

# catalogo_escolher — lê JSON do stdin; imprime o id do melhor modelo do tier
catalogo_escolher() {
  local tier="$1"
  if [ "${JSON_TOOL:-}" = node ]; then
    node -e '
const tier=process.argv[1];
const plano=(process.env.CAT_PLANO_IDS||"").split("\n").map(s=>s.trim()).filter(Boolean);
let t="";process.stdin.on("data",c=>t+=c).on("end",()=>{
  let d={};try{d=JSON.parse(t)}catch{process.exit(0)}
  const ms=Array.isArray(d.data)?d.data:[];
  const tierDe=i=>/opus/.test(i)?"opus":(/sonnet/.test(i)?"sonnet":(/haiku/.test(i)?"haiku":(/fable/.test(i)?"fable":(/mythos/.test(i)?"mythos":""))));
  // Só o que o plano libera: escolher um alias fora do plano geraria 403.
  const cand=ms.filter(m=>tierDe(m.id)===tier && (!plano.length||plano.includes(m.id)));
  if(!cand.length){process.exit(0)}
  // versão: o maior número decimal no id (5.5 > 5); empate fica em 0
  const versao=i=>{const n=[...String(i).matchAll(/(\d+(?:\.\d+)?)/g)].map(x=>parseFloat(x[1]));return n.length?Math.max(...n):0};
  const revenda=i=>/-kodeo/.test(i)?1:0;     // sufixo de revenda
  const prefixo=i=>/^kodeo-/.test(i)?1:0;    // nome de revenda, não o canônico
  cand.sort((a,b)=>
    (revenda(a.id)-revenda(b.id)) ||
    (prefixo(a.id)-prefixo(b.id)) ||
    (versao(b.id)-versao(a.id)) ||
    ((b.context_length||0)-(a.context_length||0)) ||
    String(a.id).localeCompare(String(b.id))
  );
  process.stdout.write(cand[0].id);
});' "$tier"
  else
    python3 -c '
import sys,json,re,os
tier=sys.argv[1]
plano=[s.strip() for s in os.environ.get("CAT_PLANO_IDS","").split("\n") if s.strip()]
try: d=json.load(sys.stdin)
except Exception: raise SystemExit(0)
ms=d.get("data") or []
def td(i):
    for t in ("opus","sonnet","haiku","fable","mythos"):
        if t in i: return t
    return ""
def versao(i):
    n=[float(x) for x in re.findall(r"\d+(?:\.\d+)?",str(i))]
    return max(n) if n else 0.0
cand=[m for m in ms if td(m.get("id",""))==tier and (not plano or m.get("id") in plano)]
if cand:
    cand.sort(key=lambda m:(
        1 if "-kodeo" in m["id"] else 0,
        1 if m["id"].startswith("kodeo-") else 0,
        -versao(m["id"]),
        -(m.get("context_length") or 0),
        m["id"]))
    sys.stdout.write(cand[0]["id"])
' "$tier"
  fi
}

# cat_padrao_geral → o modelo que deve ser o padrão de uma ferramenta de código
# Ordem de preferência: opus → sonnet → o primeiro anthropic → o primeiro da lista.
cat_padrao_geral() {
  local m
  for t in opus sonnet haiku fable; do
    m=$(cat_melhor_tier "$t")
    [ -n "$m" ] && { printf '%s' "$m"; return 0; }
  done
  printf '%s' "$(cat_ids | head -1)"
}

# cat_contar → quantos modelos
cat_contar() { cat_ids | grep -c . 2>/dev/null || printf '0'; }