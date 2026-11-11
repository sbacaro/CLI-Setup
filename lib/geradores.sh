#!/usr/bin/env bash
# lib/geradores.sh — monta as configurações de cada ferramenta a partir do catálogo do plano.
#
# Cada função imprime o JSON/TOML resultante no stdout e é testável sozinha:
#   bash -c '. lib/catalogo.sh; . lib/geradores.sh; claude_desktop_json ...'
#
# Regra de ouro: nenhum modelo é inventado aqui. Tudo vem de /v1/models, e o padrão é
# escolhido por critério explícito (tier certo, contexto maior, id canônico primeiro).

# ── Claude Desktop: config do Claude Desktop 3P ────────────────────────────
# Chaves conferidas contra docs oficiais (claude.com/docs/third-party/claude-desktop/configuration).
# Não existe "codeTabEnabled": o Code é ligado por "isClaudeCodeForDesktopEnabled".
# Não existe "pluginMarketplaces": o correto é "allowedPluginMarketplaces" (lista de
# URLs de marketplace). Nada de MCP remoto aqui: sem URL verificada, não se inventa.
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
  const versao=i=>{const n=[...String(i).matchAll(/(\d+(?:\.\d+)?)/g)].map(x=>parseFloat(x[1]));return n.length?Math.max(...n):0};
  const ordena=(a,b)=>
    ((/-kodeo/.test(a.id)?1:0)-(/-kodeo/.test(b.id)?1:0)) ||
    ((/^kodeo-/.test(a.id)?1:0)-(/^kodeo-/.test(b.id)?1:0)) ||
    (versao(b.id)-versao(a.id)) ||
    ((b.context_length||0)-(a.context_length||0)) ||
    String(a.id).localeCompare(String(b.id));
  const claude=ms.filter(m=>ehClaude(m.id)).sort(ordena);
  // Só modelos que o plano libera (o catálogo lista planos superiores também).
  const plano=(process.env.CAT_PLANO_IDS||"").split("\n").map(s=>s.trim()).filter(Boolean);
  const noPlano=plano.length?claude.filter(m=>plano.includes(m.id)):claude;
  // Sem aliases de revenda: "kodeo-opus-5.5" e "claude-opus-5.5-kodeo" duplicam
  // o mesmo modelo no seletor. O nome canônico ("claude-opus-5.5") já está lá.
  const semRevenda=noPlano.filter(m=>!/kodeo/i.test(m.id));
  const listaFinal=semRevenda.length?semRevenda:noPlano;
  const padraoTier={};
  for(const m of listaFinal){const t=td(m.id); if(t&&!padraoTier[t])padraoTier[t]=m.id;}
  const porId={};
  for(const m of listaFinal) porId[m.id]=m;

  const monta=(m)=>{
    const t=td(m.id);
    const nome=(m.display_name||m.id).replace(/\s*\(kodeo\)\s*$/i,"").trim();
    const o={name:m.id,labelOverride:nome};
    if(t){
      o.anthropicFamilyTier=t;
      if(padraoTier[t]===m.id)o.isFamilyDefault=true;
    }
    if((m.context_length||0)>=1000000)o.supports1m=true;
    return o;
  };
  const modelos=listaFinal.map(monta);

  const padrao=opus||padraoTier.opus||(listaFinal[0]&&listaFinal[0].id)||"";
  const cfg={
    inferenceProvider:"gateway",
    inferenceCredentialKind:"static",
    inferenceGatewayBaseUrl:base,
    inferenceGatewayApiKey:chave,
    inferenceGatewayAuthScheme:"x-api-key",
    modelDiscoveryEnabled:false,
    inferenceModels:modelos
  };
  if(padrao&&porId[padrao]){
    cfg.inferenceModels=[monta(porId[padrao]),...modelos.filter(o=>o.name!==padrao)];
  }
  // Capabilities: chaves reais do app. O Code é ligado por
  // isClaudeCodeForDesktopEnabled, não por um "codeTabEnabled" inventado.
  cfg.chatTabEnabled=true;
  cfg.coworkTabEnabled=true;
  cfg.isClaudeCodeForDesktopEnabled=true;
  cfg.autoModeEnabled=true;
  cfg.skillCreationEnabled=true;
  cfg.skillScanningEnabled=true;
  cfg.disableBundledSkills=false;
  cfg.userPluginMarketplacesEnabled=true;
  cfg.userPluginUploadsEnabled=true;
  cfg.isLocalDevMcpEnabled=true;
  cfg.mcpPersistentAlwaysAllowEnabled=true;
  // Features do app que a config 3P também controla. Sem elas o app fica
  // funcional mas capado: sem projetos, sem tarefas agendadas, sem navegador
  // embutido, sem manter a máquina acordada durante uma tarefa.
  cfg.projectsEnabled=true;
  cfg.scheduledTasksEnabled=true;
  cfg.keepAwakeEnabled=true;
  cfg.builtinBrowserEnabled=true;
  cfg.quickEntryScreenshotsEnabled=true;
  cfg.quickEntryFileSharingEnabled=true;
  // Conectores embutidos no app (server: websearch|github). Só entra o que tem
  // credencial. Montado aqui porque a junção com os locais precisa de JSON.
  const bp=(process.env.CAT_BUSCA_PROVEDOR||"").trim();
  const bk=(process.env.CAT_BUSCA_CHAVE||"").trim();
  const gid=(process.env.CAT_GITHUB_CLIENT_ID||"").trim();
  const mcp=[];
  if(bp&&bk){
    mcp.push({name:"Web search",server:"websearch",provider:bp,
              headers:{Authorization:"Bearer "+bk},
              toolPolicy:{web_search:"allow"}});
  }
  if(gid){
    mcp.push({name:"GitHub",server:"github",clientId:gid,
              toolPolicy:{merge_pull_request:"ask",delete_repository:"blocked",force_push:"blocked"}});
  }
  if(mcp.length) cfg.managedMcpServers=mcp;
  // MCP locais via stdio (npx), já com caminho absoluto resolvido pelo bash.
  const ml=(process.env.CAT_MCP_LOCAL||"").trim();
  if(ml&&ml!=="[]"){
    try{
      const extra=JSON.parse(ml);
      if(Array.isArray(extra)&&extra.length){
        cfg.managedMcpServers=[...(cfg.managedMcpServers||[]),...extra];
      }
    }catch(e){}
  }
  // MCP remotos (vendor-hosted, OAuth). O app abre o navegador no Connect.
  const mr=(process.env.CAT_MCP_REMOTO||"").trim();
  if(mr&&mr!=="[]"){
    try{
      const extra=JSON.parse(mr);
      if(Array.isArray(extra)&&extra.length){
        cfg.managedMcpServers=[...(cfg.managedMcpServers||[]),...extra];
      }
    }catch(e){}
  }
  // Marketplaces oficiais da Anthropic (allowedPluginMarketplaces).
  const mk=(process.env.CAT_MARKETPLACES||"").trim();
  if(mk&&mk!=="[]"){try{cfg.allowedPluginMarketplaces=JSON.parse(mk)}catch(e){}}
  // Egress da sandbox do Cowork.
  const eg=(process.env.CAT_EGRESS||"").trim();
  if(eg&&eg!=="[]"){try{cfg.coworkEgressAllowedHosts=JSON.parse(eg)}catch(e){}}
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
plano_ids=[s.strip() for s in os.environ.get("CAT_PLANO_IDS","").split("\n") if s.strip()]
if plano_ids: claude=[m for m in claude if m.get("id") in plano_ids]
sem_revenda=[m for m in claude if not re.search(r"kodeo", m.get("id",""), re.I)]
claude=sem_revenda if sem_revenda else claude
padrao_tier={}
for m in claude:
    t=td(m["id"])
    if t and t not in padrao_tier: padrao_tier[t]=m["id"]
modelos=[]
for m in claude:
    t=td(m["id"]); o={"name":m["id"],"labelOverride":re.sub(r"\s*\(kodeo\)\s*$","",(m.get("display_name") or m["id"]),flags=re.I).strip()}
    if t:
        o["anthropicFamilyTier"]=t
        if padrao_tier.get(t)==m["id"]: o["isFamilyDefault"]=True
    if (m.get("context_length") or 0)>=1000000: o["supports1m"]=True
    modelos.append(o)
padrao=opus or padrao_tier.get("opus") or (modelos[0]["name"] if modelos else "")
cfg={"inferenceProvider":"gateway","inferenceCredentialKind":"static",
     "inferenceGatewayBaseUrl":base,"inferenceGatewayApiKey":chave,
     "inferenceGatewayAuthScheme":"x-api-key",
     "modelDiscoveryEnabled":False,"inferenceModels":modelos}
if padrao:
    nome={o["name"]:o for o in modelos}
    prim={"name":padrao,"labelOverride":(nome.get(padrao,{}).get("labelOverride") or padrao)}
    if td(padrao):
        prim["anthropicFamilyTier"]=td(padrao); prim["isFamilyDefault"]=True
    if prim.get("supports1m") is None and (nome.get(padrao,{}).get("supports1m")): prim["supports1m"]=True
    cfg["inferenceModels"]=[prim]+[o for o in modelos if o["name"]!=padrao]
cfg.update({"chatTabEnabled":True,"coworkTabEnabled":True,
            "isClaudeCodeForDesktopEnabled":True,"autoModeEnabled":True,
            "skillCreationEnabled":True,"skillScanningEnabled":True,
            "disableBundledSkills":False,"userPluginMarketplacesEnabled":True,
            "userPluginUploadsEnabled":True,"isLocalDevMcpEnabled":True,
            "mcpPersistentAlwaysAllowEnabled":True,
            # Features do app que a config 3P também controla.
            "projectsEnabled":True,"scheduledTasksEnabled":True,
            "keepAwakeEnabled":True,"builtinBrowserEnabled":True,
            "quickEntryScreenshotsEnabled":True,
            "quickEntryFileSharingEnabled":True})
# Conectores embutidos no app: só entra o que tem credencial.
_bp=(os.environ.get("CAT_BUSCA_PROVEDOR") or "").strip()
_bk=(os.environ.get("CAT_BUSCA_CHAVE") or "").strip()
_gid=(os.environ.get("CAT_GITHUB_CLIENT_ID") or "").strip()
_mcp=[]
def _j(v):
    try: return json.loads(v) if v and v.strip() else None
    except Exception: return None
if _bp and _bk:
    _mcp.append({"name":"Web search","server":"websearch","provider":_bp,
                 "headers":{"Authorization":"Bearer "+_bk},
                 "toolPolicy":{"web_search":"allow"}})
if _gid:
    _mcp.append({"name":"GitHub","server":"github","clientId":_gid,
                 "toolPolicy":{"merge_pull_request":"ask","delete_repository":"blocked","force_push":"blocked"}})
if _mcp: cfg["managedMcpServers"]=_mcp
_ml=_j(os.environ.get("CAT_MCP_LOCAL",""))
if _ml:
    cfg["managedMcpServers"]=cfg.get("managedMcpServers",[])+_ml
_mr=_j(os.environ.get("CAT_MCP_REMOTO",""))
if _mr:
    cfg["managedMcpServers"]=cfg.get("managedMcpServers",[])+_mr
_mk=_j(os.environ.get("CAT_MARKETPLACES",""))
if _mk: cfg["allowedPluginMarketplaces"]=_mk
_eg=_j(os.environ.get("CAT_EGRESS",""))
if _eg: cfg["coworkEgressAllowedHosts"]=_eg
print(json.dumps(cfg,indent=2,ensure_ascii=False))
'
  fi
}


# ── OpenCode: todos os modelos do plano, com contexto real ──────────────────
# Regra do OpenCode: é o único app que recebe a lista inteira (todas as famílias),
# porque o seletor dele mostra o provedor junto. Mas só os modelos que o plano
# libera: o catálogo /v1/models lista planos superiores, e um deles responde
# 403 "está no Kodeo Ultra" quando o usuário tenta usar.
opencode_modelos_json() {
  printf '%s' "$CATALOGO_JSON" | catalogo_gerar_opencode
}

catalogo_gerar_opencode() {
  if [ "${JSON_TOOL:-}" = node ]; then
    node -e '
const plano=(process.env.CAT_PLANO_IDS||"").split("\n").map(s=>s.trim()).filter(Boolean);
let t="";process.stdin.on("data",c=>t+=c).on("end",()=>{
  let d={};try{d=JSON.parse(t)}catch{d={}}
  const ms=Array.isArray(d.data)?d.data:[];
  const out={};
  for(const m of ms){
    const id=m.id; if(!id)continue;
    if(plano.length&&!plano.includes(id))continue;
    const ctx=m.context_length||m.max_input_tokens||200000;
    const saida=m.max_tokens||32000;
    // formato V2: o id do mapa é o id do modelo; modelID é o que vai ao provedor
    const o={modelID:id,name:(m.display_name||id).replace(/\s*\(kodeo\)\s*$/i,"").trim(),limit:{context:ctx,output:saida}};
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
import sys,json,os,re
plano=[s.strip() for s in os.environ.get("CAT_PLANO_IDS","").split("\n") if s.strip()]
try: d=json.load(sys.stdin)
except Exception: d={}
ms=d.get("data") or []
out={}
for m in ms:
    i=m.get("id")
    if not i: continue
    if plano and i not in plano: continue
    o={"modelID":i,"name":re.sub(r"\s*\(kodeo\)\s*$","",(m.get("display_name") or i),flags=re.I).strip(),
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
  # Sem marcas de comentário. Em TOML, tudo que vem depois de um cabeçalho de
  # tabela pertence a ele — inclusive o que o próprio app escrever depois. Com
  # marcas no fim do arquivo, o app inseria `notify`, `[plugins.*]`,
  # `[mcp_servers.*]` DENTRO do trecho marcado, e o desfazer apagava tudo isso
  # junto com o provedor (49 linhas na config real). O escopo do provedor é a
  # tabela `[model_providers.kodeo]`, e é por ela que a remoção se orienta.
  printf '[model_providers.kodeo]\nname = "Kodeo"\n'
  printf 'base_url = "%s/v1"\n' "$1"
  printf 'wire_api = "responses"\n'
  printf 'env_key = "KODEO_API_KEY"\n'
  printf 'requires_openai_auth = false\n'
  printf 'http_headers = { "x-openai-actor-authorization" = "kodeo" }\n'
}

# ── Instruções do Codex/ChatGPT ────────────────────────────────────────────
# O /v1/codex/modelos traz 20 mil caracteres de base_instructions dizendo
# "You are a coding agent running in the Codex CLI ... an open source project
# led by OpenAI". É a origem da resposta "Sou o Codex CLI, criado pela OpenAI".
#
# O arquivo de catálogo é local e o app o lê a cada execução, então substituir
# esse texto muda a identidade de fato — não é cosmético. A atribuição falsa
# (dizer que é da OpenAI quando o modelo roda no gateway) é o que se corrige
# aqui; o resto das instruções de ferramenta fica a cargo do app.
#
# Vazio desliga a substituição e mantém o texto da API.
CODEX_INSTRUCOES="${KODEO_CODEX_INSTRUCOES-You are a coding agent. You run inside the Kodeo gateway, not OpenAI. Never claim to be Codex CLI or a product of OpenAI. If asked who you are, say you are an AI assistant accessed through the Kodeo gateway. Reply in the language of the user.}"

# catalogo_codex_json — o arquivo que model_catalog_json aponta.
# Usa o catálogo próprio do Codex (/v1/codex/modelos), que já vem no formato que ele lê.
# Reordenado para o primeiro item ser o modelo escolhido, e sem `base_instructions`
# duplicado em cada modelo (o config.toml já carrega o provedor).
catalogo_codex_json() { # MODELO_PADRAO
  local padrao="$1"
  printf '%s' "$CATALOGO_CODEX" | \
    CAT_PADRAO="$padrao" CAT_INSTRUCOES="${CODEX_INSTRUCOES:-}" catalogo_gerar_codex
}

# catalogo_gerar_codex — o arquivo que model_catalog_json aponta.
#
# Duas coisas que já quebraram aqui:
#
#   1. O catálogo NÃO é uma lista de nomes. O app valida cada modelo contra um
#      schema e recusa o arquivo inteiro se faltar campo ("failed to parse
#      model_catalog_json: missing field supported_reasoning_levels"). A versão
#      anterior gravava só {slug, display_name, context} e descartava 34 campos
#      do /v1/codex/modelos — o Codex ficava sem catálogo, em silêncio.
#      Agora o modelo é repassado íntegro, e só o que é nosso é alterado.
#
#   2. base_instructions é o prompt que define a identidade. O /v1/codex/modelos
#      serve 20 mil caracteres de "You are a coding agent running in the Codex
#      CLI, a terminal-based coding assistant. Codex CLI is an open source
#      project led by OpenAI" — é por isso que o app se apresentava como Codex
#      CLI. Como o arquivo é local e o app o lê a cada execução, dar-lhe outro
#      texto muda a identidade de fato (verificado: o modelo passa a se
#      apresentar como o assistente do gateway).
catalogo_gerar_codex() { # MODELO_PADRAO (vazio = usa CAT_PADRAO ou o primeiro)
  local padrao="${1:-${CAT_PADRAO:-}}"
  if [ "${JSON_TOOL:-}" = node ]; then
    CAT_PADRAO="$padrao" node -e '
const padrao=process.env.CAT_PADRAO||"";
const instrucoes=process.env.CAT_INSTRUCOES||"";
const plano=(process.env.CAT_PLANO_IDS||"").split("\n").map(s=>s.trim()).filter(Boolean);
let t="";process.stdin.on("data",c=>t+=c).on("end",()=>{
  let d={};try{d=JSON.parse(t)}catch{d={}}
  let ms=Array.isArray(d.models)?d.models:(Array.isArray(d.data)?d.data:[]);
  if(!ms.length){process.stdout.write("{\"models\":[]}\n");return;}
  const id=m=>m.slug||m.id||"";
  // 1. Só família OpenAI: o Codex/ChatGPT não deve receber Claude, Grok, GLM.
  ms=ms.filter(m=>/^gpt|^codex|^o[0-9]|openai/i.test(id(m)));
  // 2. Só o que o plano libera (senão o app lista um modelo que responde 403).
  if(plano.length) ms=ms.filter(m=>plano.includes(id(m)));
  // 3. Sem aliases de revenda: o nome canônico já está na lista.
  ms=ms.filter(m=>!/kodeo/i.test(id(m)));
  // 4. O objeto do modelo vai ÍNTEGRO — o schema do app exige os 36 campos.
  //    Só o display_name é ajustado: o app remove o prefixo "GPT-" da família
  //    OpenAI, e espaço preserva o nome no seletor ("GPT 5.5", não "5.5").
  ms=ms.map(m=>{
    if(typeof m.display_name==="string"){
      m.display_name=m.display_name.replace(/^GPT-/i,"GPT ").replace(/\s*\(kodeo\)\s*$/i,"").trim();
    }
    if(instrucoes) m.base_instructions=instrucoes;
    return m;
  });
  if(!ms.length){process.stdout.write("{\"models\":[]}\n");return;}
  if(padrao){
    const i=ms.findIndex(m=>id(m)===padrao);
    if(i>0){const [x]=ms.splice(i,1);ms.unshift(x);}
  }
  process.stdout.write(JSON.stringify({models:ms},null,2)+"\n");
});'
  else
    CAT_PADRAO="$padrao" python3 -c '
import json,os,re,sys
padrao=os.environ.get("CAT_PADRAO","")
instrucoes=os.environ.get("CAT_INSTRUCOES","")
plano=[s.strip() for s in os.environ.get("CAT_PLANO_IDS","").split("\n") if s.strip()]
try: d=json.load(sys.stdin)
except Exception: d={}
ms=d.get("models") if isinstance(d.get("models"),list) else (d.get("data") if isinstance(d.get("data"),list) else [])
def ident(m): return m.get("slug") or m.get("id") or ""
ms=[m for m in ms if re.match(r"^gpt|^codex|^o[0-9]|openai", ident(m), re.I)]
if plano: ms=[m for m in ms if ident(m) in plano]
ms=[m for m in ms if not re.search("kodeo", ident(m), re.I)]
for m in ms:
    if isinstance(m.get("display_name"),str):
        m["display_name"]=re.sub(r"^GPT-","GPT ",m["display_name"],flags=re.I)
        m["display_name"]=re.sub(r"\s*\(kodeo\)\s*$","",m["display_name"],flags=re.I).strip()
    if instrucoes: m["base_instructions"]=instrucoes
if not ms:
    print(json.dumps({"models":[]}))
else:
    if padrao:
        i=next((k for k,m in enumerate(ms) if ident(m)==padrao),-1)
        if i>0: ms.insert(0, ms.pop(i))
    print(json.dumps({"models":ms},indent=2,ensure_ascii=False))
'
  fi
}


# catalogo_chaves — lê o JSON do stdin e imprime uma chave de topo por linha.
# Usado pelo teste que confere as chaves contra a documentação oficial.
catalogo_chaves() {
  if [ "${JSON_TOOL:-}" = node ]; then
    node -e 'let t="";process.stdin.on("data",c=>t+=c).on("end",()=>{let d={};try{d=JSON.parse(t)}catch{return};Object.keys(d).forEach(k=>console.log(k))});'
  else
    python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: raise SystemExit(0)
for k in d: print(k)'
  fi
}
