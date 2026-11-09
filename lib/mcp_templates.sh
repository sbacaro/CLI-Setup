#!/usr/bin/env bash
# lib/mcp_templates.sh — templates de MCP servers populares para Claude Desktop 3P.
#
# Uso:
#   source lib/mcp_templates.sh
#   mcp_listar                    → lista todos os templates disponíveis
#   mcp_selecionar "nome"         → retorna o JSON do template
#   mcp_multiplos "nome1,nome2"   → retorna JSON com múltiplos servers
#
# Compatível com bash 3.2+ (macOS padrão)

# Templates como variáveis prefixadas (compatível com bash 3.2)
_MCP_FILESYSTEM='{"name":"filesystem","description":"Access and manage local files","transport":"streamable-http","url":"https://mcp.filesystem.example.com/sse","headers":{},"toolPolicy":{"mode":"ask","deny":["rm","rmdir","delete","del"],"allow":["*"]}}'

_MCP_GITHUB='{"name":"github","description":"GitHub API integration - repos, issues, PRs","transport":"streamable-http","url":"https://mcp.github.com/sse","headers":{},"toolPolicy":{"mode":"ask","deny":["delete_repo","force_push"],"allow":["*"]}}'

_MCP_BRAVE_SEARCH='{"name":"brave-search","description":"Web search using Brave Search API","transport":"streamable-http","url":"https://api.search.kodeo.com.br/mcp/sse","headers":{},"toolPolicy":{"mode":"allow"}}'

_MCP_MEMORY='{"name":"memory","description":"Persistent memory and context management","transport":"streamable-http","url":"https://mcp.memory.example.com/sse","headers":{},"toolPolicy":{"mode":"ask"}}'

_MCP_SLACK='{"name":"slack","description":"Slack workspace integration","transport":"streamable-http","url":"https://mcp.slack.example.com/sse","headers":{},"toolPolicy":{"mode":"ask","deny":["delete_channel"],"allow":["*"]}}'

_MCP_POSTGRES='{"name":"postgres","description":"PostgreSQL database access","command":"npx","args":["-y","@modelcontextprotocol/server-postgres"],"env":{"DATABASE_URL":"${POSTGRES_CONNECTION_STRING}"},"toolPolicy":{"mode":"ask","deny":["drop","truncate"],"allow":["*"]}}'

_MCP_SQLITE='{"name":"sqlite","description":"SQLite database operations","command":"npx","args":["-y","@modelcontextprotocol/server-sqlite","${SQLITE_PATH:-./data.db}"],"toolPolicy":{"mode":"ask","deny":["drop_table"],"allow":["*"]}}'

_MCP_AWS='{"name":"aws","description":"AWS services - S3, EC2, Lambda, etc","transport":"streamable-http","url":"https://mcp.aws.example.com/sse","headers":{},"toolPolicy":{"mode":"ask","deny":["delete_bucket","terminate_instances"],"allow":["*"]}}'

_MCP_SEQUENTIAL_THINKING='{"name":"sequential-thinking","description":"Advanced reasoning and problem solving","command":"npx","args":["-y","@modelcontextprotocol/server-sequential-thinking"],"toolPolicy":{"mode":"allow"}}'

_MCP_GOOGLE_MAPS='{"name":"google-maps","description":"Google Maps API integration","transport":"streamable-http","url":"https://mcp.googlemaps.example.com/sse","headers":{},"toolPolicy":{"mode":"ask"}}'

_MCP_FIGMA='{"name":"figma","description":"Figma design files integration","transport":"streamable-http","url":"https://mcp.figma.example.com/sse","headers":{},"toolPolicy":{"mode":"ask"}}'

_MCP_NOTION='{"name":"notion","description":"Notion workspace integration","transport":"streamable-http","url":"https://mcp.notion.example.com/sse","headers":{},"toolPolicy":{"mode":"ask","deny":["delete_page","delete_database"],"allow":["*"]}}'

# Lista de todos os nomes de MCP servers
MCP_DISPONIVEIS="filesystem github brave-search memory slack postgres sqlite aws sequential-thinking google-maps figmap notion"

# Função para obter template por nome
mcp_get() {
  local nome="$1"
  case "$nome" in
    filesystem)        printf '%s' "$_MCP_FILESYSTEM" ;;
    github)           printf '%s' "$_MCP_GITHUB" ;;
    brave-search)     printf '%s' "$_MCP_BRAVE_SEARCH" ;;
    memory)           printf '%s' "$_MCP_MEMORY" ;;
    slack)            printf '%s' "$_MCP_SLACK" ;;
    postgres)         printf '%s' "$_MCP_POSTGRES" ;;
    sqlite)           printf '%s' "$_MCP_SQLITE" ;;
    aws)              printf '%s' "$_MCP_AWS" ;;
    sequential-thinking) printf '%s' "$_MCP_SEQUENTIAL_THINKING" ;;
    google-maps)      printf '%s' "$_MCP_GOOGLE_MAPS" ;;
    figma)            printf '%s' "$_MCP_FIGMA" ;;
    notion)           printf '%s' "$_MCP_NOTION" ;;
    *)                return 1 ;;
  esac
}

# Lista todos os templates disponíveis
mcp_listar() {
  echo "$MCP_DISPONIVEIS" | tr ' ' '\n'
}

# Retorna o JSON de um template específico
mcp_selecionar() {
  local nome="$1"
  if [ -n "$nome" ]; then
    mcp_get "$nome"
    return 0
  fi
  return 1
}

# Retorna JSON array com múltiplos templates
mcp_multiplos() {
  local IFS=',' selecao="$1"
  local primeiro=1
  
  printf '['
  for nome in $selecao; do
    local trimmed; trimmed=$(echo "$nome" | xargs)
    if [ -n "$trimmed" ]; then
      local template; template=$(mcp_get "$trimmed" 2>/dev/null)
      if [ -n "$template" ]; then
        [ "$primeiro" -eq 0 ] && printf ',' || primeiro=0
        printf '%s' "$template"
      fi
    fi
  done
  printf ']'
}

# Gera JSON de MCP servers com substituição de variáveis de ambiente
mcp_gerar_com_env() {
  local servers_json="$1"
  local saida
  
  if [ "${JSON_TOOL:-}" = node ]; then
    saida=$(printf '%s' "$servers_json" | node -e '
const fs=require("fs");
let t="";process.stdin.on("data",c=>t+=c).on("end",()=>{
  let arr=[];try{arr=JSON.parse(t)}catch{process.stdout.write("[]");return}
  const out=arr.map(s=>{
    const replaced=JSON.stringify(s).replace(/\$\{([^}]+)\}/g,(_,k)=>{
      const v=process.env[k]||process.env[k.replace(/_/g,"").toUpperCase()]||"";
      return v;
    });
    return JSON.parse(replaced);
  });
  process.stdout.write(JSON.stringify(out,null,2));
});')
  else
    saida=$(printf '%s' "$servers_json" | python3 -c '
import sys,json,os,re
try: arr=json.load(sys.stdin)
except: print("[]");sys.exit(0)
def subst(v):
    def repl(m):
        k=m.group(1)
        return os.environ.get(k) or os.environ.get(k.upper().replace("_","")) or ""
    return re.sub(r"\$\{([^}]+)\}",repl,v)
out=[]
for s in arr:
    out.append(json.loads(subst(json.dumps(s))))
print(json.dumps(out,indent=2,ensure_ascii=False))
')
  fi
  printf '%s' "$saida"
}
