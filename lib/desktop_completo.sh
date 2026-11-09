#!/usr/bin/env bash
# lib/desktop_completo.sh — configurações avançadas do Claude Desktop 3P.
#
# Complementa geradores.sh com funcionalidades que o Claude Desktop 3P oferece
# mas não vem habilitadas por padrão quando se usa third-party inference:
#   - Skills (criação, scanning, bundled)
#   - Plugins (marketplaces, uploads)
#   - MCP servers (managed e locais)
#   - Capabilities (Chat, Cowork, Code tabs)
#   - Egress allowlist para a sandbox

# ── Capacidades do Desktop 3P ────────────────────────────────────────────────

# desktop_capabilities_json → JSON com todas as capacidades habilitadas
desktop_capabilities_json() {
  cat <<'EOF'
{
  "chatTabEnabled": true,
  "coworkTabEnabled": true,
  "codeTabEnabled": true,
  "autoModeEnabled": true,
  "skillCreationEnabled": true,
  "skillScanningEnabled": true,
  "disableBundledSkills": false,
  "userPluginMarketplacesEnabled": true,
  "userPluginUploadsEnabled": true,
  "isLocalDevMcpEnabled": true,
  "mcpPersistentAlwaysAllowEnabled": true
}
EOF
}

# ── Egress Allowlist ──────────────────────────────────────────────────────────

# desktop_egress_json → JSON com egress hosts típicos
# Adicione/remova domínios conforme necessário
desktop_egress_json() {
  cat <<'EOF'
{
  "coworkEgressAllowedHosts": [
    "github.com",
    "api.github.com",
    "pypi.org",
    "registry.npmjs.org",
    "npmjs.org",
    "*.github.com",
    "*.githubusercontent.com",
    "github.dev",
    "gitlab.com",
    "bitbucket.org"
  ]
}
EOF
}

# desktop_egress_minimo → só o mínimo para funcionar
desktop_egress_minimo() {
  cat <<'EOF'
{
  "coworkEgressAllowedHosts": [
    "github.com",
    "api.github.com"
  ]
}
EOF
}

# desktop_egress_completo → para desenvolvedores
desktop_egress_completo() {
  cat <<'EOF'
{
  "coworkEgressAllowedHosts": [
    "github.com",
    "api.github.com",
    "pypi.org",
    "registry.npmjs.org",
    "npmjs.org",
    "*.github.com",
    "*.githubusercontent.com",
    "github.dev",
    "gitlab.com",
    "gitlab.org",
    "bitbucket.org",
    "bitbucket.org",
    "docker.io",
    "registry.terraform.io",
    "registry.helm.sh",
    "charts.helm.sh"
  ]
}
EOF
}

# ── Skills e Plugins ──────────────────────────────────────────────────────────

# desktop_skills_json → configuração de skills
desktop_skills_json() {
  cat <<'EOF'
{
  "skillCreationEnabled": true,
  "skillScanningEnabled": true,
  "disableBundledSkills": false
}
EOF
}

# desktop_plugins_json → configuração de plugins
desktop_plugins_json() {
  cat <<'EOF'
{
  "userPluginMarketplacesEnabled": true,
  "userPluginUploadsEnabled": true
}
EOF
}

# desktop_plugins_com_marketplace_json MARKETPLACE_URL → inclui marketplace específico
desktop_plugins_com_marketplace_json() {
  local url="$1"
  if [ -n "$url" ]; then
    cat <<EOF
{
  "userPluginMarketplacesEnabled": true,
  "userPluginUploadsEnabled": true,
  "pluginMarketplaces": ["$url"]
}
EOF
  else
    desktop_plugins_json
  fi
}

# ── Configuração Completa do Desktop 3P ───────────────────────────────────────

# desktop_config_completo BASE CHAVE MCP_SERVERS EGRESS MARKETPLACE
# Monta o JSON completo para Claude Desktop com tudo habilitado
desktop_config_completo() {
  local base="$1" chave="$2" mcp_servers="$3" egress="$4" marketplace="$5"
  
  # Base config de geradores.sh (vindo via stdin do catalogo)
  local base_json
  base_json=$(cat)
  
  # Campos adicionais de capabilities
  local caps; caps=$(desktop_capabilities_json)
  
  # Egress
  local eg
  case "$egress" in
    minimo)    eg=$(desktop_egress_minimo) ;;
    completo)  eg=$(desktop_egress_completo) ;;
    *)         eg=$(desktop_egress_json) ;;
  esac
  
  # Plugins com marketplace se fornecido
  local plugins
  if [ -n "$marketplace" ]; then
    plugins=$(desktop_plugins_com_marketplace_json "$marketplace")
  else
    plugins=$(desktop_plugins_json)
  fi
  
  # Merge tudo
  if [ "${JSON_TOOL:-}" = node ]; then
    printf '%s' "$base_json" | node -e "
const base=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
const caps=JSON.parse('$caps');
const eg=JSON.parse('$eg');
const plugins=JSON.parse('$plugins');
const mcp=$([ -n '$mcp_servers' ] && '$mcp_servers' !== '[]' ? '$mcp_servers' : 'null');
const merge={...caps,...eg,...plugins};
if(mcp) merge.managedMcpServers=mcp;
const out={...base,...merge};
process.stdout.write(JSON.stringify(out,null,2)+'\n');
"
  else
    printf '%s' "$base_json" | python3 -c "
import sys,json
base=json.load(sys.stdin)
caps=json.loads('''$caps''')
eg=json.loads('''$eg''')
plugins=json.loads('''$plugins''')
mcp=$([ -n '$mcp_servers' ] and '$mcp_servers' != '[]' and '$mcp_servers' != '' and '$mcp_servers' != 'null' and '$mcp_servers' != 'undefined' and '$mcp_servers' != '\"\"' and '$mcp_servers' != '''[]''' and '$mcp_servers' != '\"null\"' and '$mcp_servers' != '\"undefined\"' and '$mcp_servers' != '\"\"' and '$mcp_servers' != '' and '$mcp_servers' != 'null' and '$mcp_servers' != 'undefined' and '$mcp_servers' != '\"\"' and '$mcp_servers' != '''[]''' and '$mcp_servers' != '\"null\"' and '$mcp_servers' != '\"undefined\"' ? '''$mcp_servers''' : 'null')
merge={**caps,**eg,**plugins}
if mcp: merge['managedMcpServers']=mcp
out={**base,**merge}
print(json.dumps(out,indent=2,ensure_ascii=False))
"
  fi
}

# ── Geração de Config com Modelo Padrão ──────────────────────────────────────

# desktop_config_final BASE CHAVE MODELO_PADRAO [MCP_SERVERS] [EGRESS] [MARKETPLACE]
# Gera a config completa combinando com o catálogo de modelos
desktop_config_final() {
  local base="$1" chave="$2" modelo="$3" mcp_servers="${4:-}" egress="${5:-padrao}" marketplace="${6:-}"
  
  # Pegar modelo padrão do catálogo
  local padrao="${modelo:-$(cat_padrao_geral 2>/dev/null)}"
  
  # Gerar base config com modelo padrão
  printf '%s' "$CATALOGO_JSON" | \
    CAT_BASE="$base" \
    CAT_CHAVE="$chave" \
    CAT_OPUS="$padrao" \
    catalogo_gerar_claude_completo "$mcp_servers" "$egress" "$marketplace"
}

# catalogo_gerar_claude_completo — versão expandida com todas as features
catalogo_gerar_claude_completo() {
  local mcp_servers="$1" egress="$2" marketplace="$3"
  
  if [ "${JSON_TOOL:-}" = node ]; then
    node -e '
const mcpServersArg="'$mcp_servers'";
const egressArg="'$egress'";
const marketplaceArg="'$marketplace'";

let t="";process.stdin.on("data",c=>t+=c).on("end",()=>{
  let d={};try{d=JSON.parse(t)}catch{d={}}
  const ms=Array.isArray(d.data)?d.data:[];
  
  // Ordenação padrão
  const td=i=>i.match(/opus/)?"opus":(i.match(/sonnet/)?"sonnet":(i.match(/haiku/)?"haiku":(i.match(/fable/)?"fable":(i.match(/mythos/)?"mythos":""))));
  const ehClaude=i=>/claude|anthropic|opus|fable|sonnet|haiku|mythos/i.test(i);
  const versao=i=>{const n=[...String(i).matchAll(/(\d+(?:\.\d+)?)/g)].map(x=>parseFloat(x[1]));return n.length?Math.max(...n):0};
  const ordena=(a,b)=>
    ((/-kodeo/.test(a.id)?1:0)-(/-kodeo/.test(b.id)?1:0)) ||
    ((/^kodeo-/.test(a.id)?1:0)-(/^kodeo-/.test(b.id)?1:0)) ||
    (versao(b.id)-versao(a.id)) ||
    ((b.context_length||0)-(a.context_length||0)) ||
    String(a.id).localeCompare(String(b.id));
  
  const claude=ms.filter(m=>ehClaude(m.id)).sort(ordena);
  const padraoTier={};
  for(const m of claude){const t=td(m.id); if(t&&!padraoTier[t])padraoTier[t]=m.id;}
  const porId={}; for(const m of claude) porId[m.id]=m;
  
  const monta=(m)=>{
    const t=td(m.id);
    const o={name:m.id,labelOverride:m.display_name||m.id};
    if(t){o.anthropicFamilyTier=t; if(padraoTier[t]===m.id)o.isFamilyDefault=true;}
    if((m.context_length||0)>=1000000)o.supports1m=true;
    return o;
  };
  
  const modelos=claude.map(monta);
  const padrao=padraoTier.opus||(claude[0]&&claude[0].id)||"";
  
  // Base config
  const base=process.env.CAT_BASE||"";
  const chave=process.env.CAT_CHAVE||"";
  const cfg={
    inferenceProvider:"gateway",
    inferenceCredentialKind:"static",
    inferenceGatewayBaseUrl:base,
    inferenceGatewayApiKey:chave,
    modelDiscoveryEnabled:false,
    inferenceModels:modelos
  };
  
  if(padrao&&porId[padrao]){
    cfg.inferenceModels=[monta(porId[padrao]),...modelos.filter(o=>o.name!==padrao)];
  }
  
  // Capabilities completas
  cfg.chatTabEnabled=true;
  cfg.coworkTabEnabled=true;
  cfg.codeTabEnabled=true;
  cfg.autoModeEnabled=true;
  cfg.skillCreationEnabled=true;
  cfg.skillScanningEnabled=true;
  cfg.disableBundledSkills=false;
  cfg.userPluginMarketplacesEnabled=true;
  cfg.userPluginUploadsEnabled=true;
  cfg.isLocalDevMcpEnabled=true;
  cfg.mcpPersistentAlwaysAllowEnabled=true;
  
  // Egress
  const egressMinimo=["github.com","api.github.com"];
  const egressPadrao=["github.com","api.github.com","pypi.org","registry.npmjs.org","npmjs.org","*.github.com","*.githubusercontent.com","github.dev"];
  const egressCompleto=["github.com","api.github.com","pypi.org","registry.npmjs.org","npmjs.org","*.github.com","*.githubusercontent.com","github.dev","gitlab.com","gitlab.org","bitbucket.org","docker.io"];
  
  let egress=egressPadrao;
  if(egressArg==="minimo") egress=egressMinimo;
  else if(egressArg==="completo") egress=egressCompleto;
  cfg.coworkEgressAllowedHosts=egress;
  
  // Marketplace
  if(marketplaceArg) cfg.pluginMarketplaces=[marketplaceArg];
  
  // MCP servers
  if(mcpServersArg&&mcpServersArg!=="[]"&&mcpServersArg!==""&&mcpServersArg!=="null"){
    try{
      const mcp=JSON.parse(mcpServersArg);
      if(Array.isArray(mcp)&&mcp.length>0){
        cfg.managedMcpServers=mcp;
      }
    }catch(e){}
  }
  
  process.stdout.write(JSON.stringify(cfg,null,2)+"\n");
});'
  else
    python3 -c '
import sys,json,os,re
mcp_arg="'$mcp_servers'"
egress_arg="'$egress'"
marketplace_arg="'$marketplace'"

try: d=json.load(sys.stdin)
except: d={}
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

padrao=padrao_tier.get("opus") or (modelos[0]["name"] if modelos else "")
base=os.environ.get("CAT_BASE","");chave=os.environ.get("CAT_CHAVE","")

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

# Capabilities
cfg.update({
    "chatTabEnabled":True,"coworkTabEnabled":True,"codeTabEnabled":True,
    "autoModeEnabled":True,"skillCreationEnabled":True,"skillScanningEnabled":True,
    "disableBundledSkills":False,"userPluginMarketplacesEnabled":True,
    "userPluginUploadsEnabled":True,"isLocalDevMcpEnabled":True,
    "mcpPersistentAlwaysAllowEnabled":True
})

# Egress
if egress_arg=="minimo":
    cfg["coworkEgressAllowedHosts"]=["github.com","api.github.com"]
elif egress_arg=="completo":
    cfg["coworkEgressAllowedHosts"]=["github.com","api.github.com","pypi.org","registry.npmjs.org","npmjs.org","*.github.com","*.githubusercontent.com","github.dev","gitlab.com","gitlab.org","bitbucket.org","docker.io"]
else:
    cfg["coworkEgressAllowedHosts"]=["github.com","api.github.com","pypi.org","registry.npmjs.org","npmjs.org","*.github.com","*.githubusercontent.com","github.dev"]

# Marketplace
if marketplace_arg: cfg["pluginMarketplaces"]=[marketplace_arg]

# MCP servers
if mcp_arg and mcp_arg not in ("[]","","null","undefined"):
    try:
        mcp=json.loads(mcp_arg)
        if isinstance(mcp,list) and mcp:
            cfg["managedMcpServers"]=mcp
    except: pass

print(json.dumps(cfg,indent=2,ensure_ascii=False))
'
  fi
}

# ── Help para usuários ────────────────────────────────────────────────────────

desktop_help_mcp() {
  cat <<'HELPEOF'
# MCP Servers Disponíveis para Claude Desktop 3P

O CLI Setup suporta os seguintes MCP servers pré-configurados:

## Servidores Remotos (HTTP/SSE)

1. **filesystem** - Acesso a sistema de arquivos local
2. **github** - Integração com GitHub (repos, issues, PRs)
3. **brave-search** - Busca na web via Brave Search
4. **memory** - Memória persistente e gerenciamento de contexto
5. **slack** - Integração com workspace Slack
6. **aws** - Serviços AWS (S3, EC2, Lambda, etc)
7. **google-maps** - Integração com Google Maps API
8. **figma** - Integração com arquivos do Figma
9. **notion** - Integração com workspace Notion

## Servidores Locais (stdio)

10. **postgres** - Acesso a banco PostgreSQL (requer DATABASE_URL)
11. **sqlite** - Operações com banco SQLite
12. **sequential-thinking** - Raciocínio avançado e resolução de problemas

## Configuração de Exemplo

Para adicionar múltiplos servers, separe por vírgula:
  filesystem,github,brave-search

## Variáveis de Ambiente

Alguns servers requerem variáveis de ambiente:
  DATABASE_URL - Connection string do PostgreSQL
  POSTGRES_CONNECTION_STRING - Alias para DATABASE_URL
  SQLITE_PATH - Caminho para arquivo SQLite (padrão: ./data.db)

HELPEOF
}
