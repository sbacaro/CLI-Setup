#!/usr/bin/env bash
# lib/geradores.sh — monta as configurações de cada ferramenta a partir do catálogo do plano.
#
# Cada função imprime o JSON/TOML resultante no stdout e é testável sozinha:
#   bash -c '. lib/catalogo.sh; . lib/geradores.sh; claude_desktop_json ...'
#
# Regra de ouro: nenhum modelo é inventado aqui. Tudo vem de /v1/models, e o padrão é
# escolhido por critério explícito (tier certo, contexto maior, id canônico primeiro).

# ── Claude Desktop: inferenceModels ─────────────────────────────────────────
# O app só monta o seletor a partir de /v1/models se o id "parecer Claude", e os atalhos
# de tier (Opus/Sonnet/Haiku) só aparecem com inferenceModels explícito. Então listamos
# todos os modelos, marcando o tier e o padrão de cada tier.
#
# Saída: o conteúdo de um arquivo do configLibrary, pronto para gravar.
claude_desktop_json() { # BASE CHAVE → JSON
  local base="$1" chave="$2"
  printf '%s' "$CATALOGO_JSON" | CAT_BASE="$base" CAT_CHAVE="$chave" CAT_OPUS="$OPUS_ID" catalogo_gerar_claude
}

catalogo_gerar_claude() {
  if [ "${JSON_TOOL:-}" = node ]; then
    node -e '
const base=process.env.CAT_BASE, chave=process.env.CAT_CHAVE, opus=process.env.CAT_OPUS||"";
let t="";process.stdin.on("data",c=>t+=c).on("end",()=>{
  let d={};try{d=JSON.parse(t)}catch{d={}}
  const ms=Array.isArray(d.data)?d.data:[];
  const td=i=>/opus/.test(i)?"opus":(/sonnet/.test(i)?"sonnet":(/haiku/.test(i)?"haiku":(/fable/.test(i)?"fable":(/mythos/.test(i)?"mythos":""))));
  const ehClaude=i=>/claude|anthropic|opus|fable|sonnet|haiku|mythos/i.test(i);
  // o mesmo critério de cat_melhor_tier: canônico, sem revenda, maior versão, maior contexto
  const versao=i=>{const n=[...String(i).matchAll(/(\d+(?:\.\d+)?)/g)].map(x=>parseFloat(x[1]));return n.length?Math.max(...n):0};
  const ordena=(a,b)=>
    ((/-kodeo/.test(a.id)?1:0)-(/-kodeo/.test(b.id)?1:0)) ||
    ((/^kodeo-/.test(a.id)?1:0)-(/^kodeo-/.test(b.id)?1:0)) ||
    (versao(b.id)-versao(a.id)) ||
    ((b.context_length||0)-(a.context_length||0)) ||
    String(a.id).localeCompare(String(b.id));
  const claude=ms.filter(m=>ehClaude(m.id)).sort(ordena);
  // o melhor de cada tier, pela mesma ordem acima
  const padraoTier={};
  for(const m of claude){const t=td(m.id); if(t&&!padraoTier[t])padraoTier[t]=m.id;}
  const porId={};
  for(const m of claude) porId[m.id]=m;

  const monta=(m)=>{
    const t=td(m.id);
    const o={name:m.id,labelOverride:m.display_name||m.id};
    if(t){
      o.anthropicFamilyTier=t;
      if(padraoTier[t]===m.id)o.isFamilyDefault=true;
    }
    if((m.context_length||0)>=1000000)o.supports1m=true;
    return o;
  };
  const modelos=claude.map(monta);

  // padrão global: o Opus do plano, senão o primeiro Claude
  const padrao=opus||padraoTier.opus||(claude[0]&&claude[0].id)||"";
  const cfg={
    inferenceProvider:"gateway",
    inferenceCredentialKind:"static",
    inferenceGatewayBaseUrl:base,
    inferenceGatewayApiKey:chave,
    modelDiscoveryEnabled:false,
    inferenceModels:modelos
  };
  // O primeiro item da lista é o modelo inicial do app
  if(padrao&&porId[padrao]){
    cfg.inferenceModels=[monta(porId[padrao]),...modelos.filter(o=>o.name!==padrao)];
  }
  process.stdout.write(JSON.stringify(cfg,null,2)+"\n");
});' 
  else
    python3 -c '
import sys,json,os,re
base=os.environ.get("CAT_BASE","");chave=os.environ.get("CAT_CHAVE","");opus=os.environ.get("CAT_OPUS","")
try: d=json.load(sys.stdin)
except Exception: d={}
ms=d.get("data") or []
def td(i):
    for t in ("opus","sonnet","haiku","fable","mythos"):
        if t in i: return t
    return ""
def eh(i): return bool(re.search(r"claude|anthropic|opus|fable|sonnet|haiku|mythos",i,re.I))
def versao(i):
    n=[float(x) for x in re.findall(r"\d+(?:\.\d+)?",str(i))]
    return max(n) if n else 0.0
def ordena(m):
    i=m.get("id","")
    return (1 if "-kodeo" in i else 0, 1 if i.startswith("kodeo-") else 0,
            -versao(i), -(m.get("context_length") or 0), i)
claude=sorted([m for m in ms if eh(m.get("id",""))], key=ordena)
padrao_tier={}
for m in claude:
    t=td(m["id"])
    if t and t not in padrao_tier: padrao_tier[t]=m["id"]
modelos=[]
for m in claude:
    t=td(m["id"]); o={"name":m["id"],"labelOverride":m.get("display_name") or m["id"]}
    if t:
        o["anthropicFamilyTier"]=t
        if padrao_tier.get(t)==m["id"]: o["isFamilyDefault"]=True
    if (m.get("context_length") or 0)>=1000000: o["supports1m"]=True
    modelos.append(o)
padrao=opus or padrao_tier.get("opus") or (modelos[0]["name"] if modelos else "")
cfg={"inferenceProvider":"gateway","inferenceCredentialKind":"static",
     "inferenceGatewayBaseUrl":base,"inferenceGatewayApiKey":chave,
     "modelDiscoveryEnabled":False,"inferenceModels":modelos}
if padrao:
    nome={o["name"]:o for o in modelos}
    prim={"name":padrao,"labelOverride":(nome.get(padrao,{}).get("labelOverride") or padrao)}
    if td(padrao):
        prim["anthropicFamilyTier"]=td(padrao); prim["isFamilyDefault"]=True
    if prim.get("supports1m") is None and (nome.get(padrao,{}).get("supports1m")): prim["supports1m"]=True
    cfg["inferenceModels"]=[prim]+[o for o in modelos if o["name"]!=padrao]
print(json.dumps(cfg,indent=2,ensure_ascii=False))
'
  fi
}

# ── OpenCode: todos os modelos, com contexto real ───────────────────────────
opencode_modelos_json() {
  printf '%s' "$CATALOGO_JSON" | catalogo_gerar_opencode
}

catalogo_gerar_opencode() {
  if [ "${JSON_TOOL:-}" = node ]; then
    node -e '
let t="";process.stdin.on("data",c=>t+=c).on("end",()=>{
  let d={};try{d=JSON.parse(t)}catch{d={}}
  const ms=Array.isArray(d.data)?d.data:[];
  const out={};
  for(const m of ms){
    const id=m.id; if(!id)continue;
    const ctx=m.context_length||m.max_input_tokens||200000;
    const saida=m.max_tokens||32000;
    // formato V2: o id do mapa é o id do modelo; modelID é o que vai ao provedor
    const o={modelID:id,name:m.display_name||id,limit:{context:ctx,output:saida}};
    const caps=m.capabilities||{};
    const entrada=[];
    if(caps.image_input&&caps.image_input.supported)entrada.push("image");
    if(caps.pdf_input&&caps.pdf_input.supported)entrada.push("pdf");
    o.capabilities={tools:true,input:entrada.length?["text",...entrada]:["text"],output:["text"]};
    if(caps.thinking&&caps.thinking.supported)o.capabilities.reasoning=true;
    out[id]=o;
  }
  process.stdout.write(JSON.stringify(out,null,2));
});'
  else
    python3 -c '
import sys,json
try: d=json.load(sys.stdin)
except Exception: d={}
ms=d.get("data") or []
out={}
for m in ms:
    i=m.get("id")
    if not i: continue
    o={"modelID":i,"name":m.get("display_name") or i,
       "limit":{"context":m.get("context_length") or m.get("max_input_tokens") or 200000,
                "output":m.get("max_tokens") or 32000}}
    caps=m.get("capabilities") or {}
    entrada=[]
    if (caps.get("image_input") or {}).get("supported"): entrada.append("image")
    if (caps.get("pdf_input") or {}).get("supported"): entrada.append("pdf")
    o["capabilities"]={"tools":True,"input":["text"]+entrada,"output":["text"]}
    if (caps.get("thinking") or {}).get("supported"): o["capabilities"]["reasoning"]=True
    out[i]=o
print(json.dumps(out,indent=2,ensure_ascii=False))
'
  fi
}

# ── Claude Code: variáveis de modelo por tier ──────────────────────────────
# Só define a variável do tier que existe no plano. Um tier ausente fica sem variável,
# em vez de apontar para outro modelo (o que fazia "Sonnet" virar outro provedor).
claude_code_env() { # BASE CHAVE → linhas CHAVE=valor
  local base="$1" chave="$2" opus="$3" sonnet="$4" haiku="$5"
  printf 'ANTHROPIC_BASE_URL=%s\n' "$base"
  printf 'ANTHROPIC_AUTH_TOKEN=%s\n' "$chave"
  [ -n "$opus" ]   && printf 'ANTHROPIC_DEFAULT_OPUS_MODEL=%s\n' "$opus"
  [ -n "$sonnet" ] && printf 'ANTHROPIC_DEFAULT_SONNET_MODEL=%s\n' "$sonnet"
  [ -n "$haiku" ]  && printf 'ANTHROPIC_DEFAULT_HAIKU_MODEL=%s\n' "$haiku"
  printf 'CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1\n'
  return 0
}
# ── Codex CLI / ChatGPT Desktop: config.toml ───────────────────────────────
# Os dois leem o MESMO ~/.codex/config.toml. Duas coisas importam:
#  1. `model` explícito. Sem ele o app ordena o catálogo por `priority`, e o primeiro
#     da lista da API é o minimax — era isso que fazia "quase tudo" cair no MiniMax.
#  2. `model_catalog_json` apontando para a lista do plano, para o seletor mostrar os
#     modelos certos em vez do catálogo da OpenAI.
cx_bloco_topo() { # MODELO [CATALOGO]
  printf '# >>> kodeo >>>\nmodel = "%s"\nmodel_provider = "kodeo"\n' "$1"
  [ -n "${2:-}" ] && printf 'model_catalog_json = "%s"\n' "$2"
  printf '# <<< kodeo <<<\n'
}

cx_bloco_provider() { # BASE
  printf '# >>> kodeo provider >>>\n[model_providers.kodeo]\nname = "Kodeo"\n'
  printf 'base_url = "%s/v1"\n' "$1"
  printf 'wire_api = "responses"\n'
  printf 'env_key = "KODEO_API_KEY"\n'
  printf 'requires_openai_auth = false\n'
  printf 'http_headers = { "x-openai-actor-authorization" = "kodeo" }\n'
  printf '# <<< kodeo provider <<<\n'
}

# catalogo_codex_json — o arquivo que model_catalog_json aponta.
# Usa o catálogo próprio do Codex (/v1/codex/modelos), que já vem no formato que ele lê.
# Reordenado para o primeiro item ser o modelo escolhido, e sem `base_instructions`
# duplicado em cada modelo (o config.toml já carrega o provedor).
catalogo_codex_json() { # MODELO_PADRAO
  local padrao="$1"
  printf '%s' "$CATALOGO_CODEX" | CAT_PADRAO="$padrao" catalogo_gerar_codex
}

catalogo_gerar_codex() {
  if [ "${JSON_TOOL:-}" = node ]; then
    node -e '
const padrao=process.env.CAT_PADRAO||"";
let t="";process.stdin.on("data",c=>t+=c).on("end",()=>{
  let d={};try{d=JSON.parse(t)}catch{d={}}
  let ms=Array.isArray(d.models)?d.models:(Array.isArray(d.data)?d.data:[]);
  if(!ms.length){process.stdout.write("{\"models\":[]}\n");return;}
  if(padrao){
    const i=ms.findIndex(m=>(m.slug||m.id)===padrao);
    if(i>0){const [x]=ms.splice(i,1);ms.unshift(x);}
  }
  process.stdout.write(JSON.stringify({models:ms},null,2)+"\n");
});'
  else
    python3 -c '
import sys,json,os
padrao=os.environ.get("CAT_PADRAO","")
try: d=json.load(sys.stdin)
except Exception: d={}
ms=d.get("models") if isinstance(d.get("models"),list) else (d.get("data") if isinstance(d.get("data"),list) else [])
if padrao:
    for i,m in enumerate(ms):
        if (m.get("slug") or m.get("id"))==padrao:
            if i>0: ms.insert(0,ms.pop(i))
            break
print(json.dumps({"models":ms},indent=2,ensure_ascii=False))
'
  fi
}
