#!/usr/bin/env bash
# lib/desktop.sh — configuração do Claude Desktop 3P para ficar equivalente ao app
# com assinatura Anthropic.
#
# O problema: ao apontar o app para um gateway, ele sai do modo Anthropic e perde
# conectores, skills e plugins. Tudo que ele recebia do Console da Anthropic deixa
# de existir. A config abaixo devolve essas camadas por caminhos que FUNCIONAM sem
# infraestrutura da Anthropic, sem inventar nenhum host:
#
#   1. Conectores embutidos no app (server: websearch | github). Rodam como processo
#      local na máquina do usuário. Nada passa por host da Anthropic.
#   2. Skills e plugins pelos marketplaces oficiais da Anthropic no GitHub,
#      Apache 2.0 — os mesmos repositórios que alimentam o Claude real.
#   3. Plugins de organização pelo diretório /Library/Application Support/Claude/org-plugins/.
#
# Cada valor foi conferido na documentação oficial
# (claude.com/docs/third-party/claude-desktop) ou é um repositório público real.

# ── Marketplaces oficiais da Anthropic ──────────────────────────────────────
# Ambos são repositórios públicos, sem autenticação, com .claude-plugin/marketplace.json.
# "ref" vazio rastreia o branch padrão: sempre a versão mais recente, sem valor
# fixo que envelhece. A doc exige SHA de 40 caracteres apenas quando
# installationPreference é auto_install/required — aqui é "available", então
# branch é aceito e preferível.
SKILLS_REPO="${KODEO_SKILLS_REPO:-anthropics/skills}"
SKILLS_NAME="anthropic-agent-skills"
# anthropics/claude-code NÃO é um marketplace: é o repositório do produto. Seu
# .claude-plugin/marketplace.json lista 12 plugins e TODOS declaram "source"
# como objeto ({source:"git-subdir",url:...}), forma que o app trata como
# "external" e descarta do host install — o log dizia "12 external-source
# plugin(s) excluded from host install" e sobrava zero plugin instalável.
# O diretório oficial é anthropics/claude-plugins-official: 317 plugins, dos
# quais 54 declaram "source" como caminho relativo e instalam de fato.
CODE_REPO="${KODEO_CODE_PLUGINS_REPO:-anthropics/claude-plugins-official}"
CODE_NAME="claude-plugins-official"

# desktop_marketplaces_json → array JSON dos marketplaces permitidos.
# INCLUIR_SKILLS (1|0), INCLUIR_CODE (1|0)
desktop_marketplaces_json() {
  local sk="${1:-1}" cc="${2:-1}" out="" sep=""
  if [ "$sk" = "1" ]; then
    out="$out$sep{\"source\":\"github\",\"repo\":\"$SKILLS_REPO\",\"expectedName\":\"$SKILLS_NAME\",\"credentialKind\":\"anonymous\",\"installationPreference\":\"available\"}"
    sep=","
  fi
  if [ "$cc" = "1" ]; then
    out="$out$sep{\"source\":\"github\",\"repo\":\"$CODE_REPO\",\"expectedName\":\"$CODE_NAME\",\"credentialKind\":\"anonymous\",\"installationPreference\":\"available\"}"
    sep=","
  fi
  printf '[%s]' "$out"
}

# ── Egress allowlist ────────────────────────────────────────────────────────
# Hosts que a sandbox do Cowork pode alcançar. Sem isso, Web Fetch e o shell
# dentro da sandbox não saem. Inclui os hosts do marketplace (github) e os
# provedores de busca (o conector websearch roda fora da sandbox, mas o Web
# Fetch dos resultados precisa passar).
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
        deb.debian.org archive.ubuntu.com security.ubuntu.com \
        api.search.brave.com api.tavily.com api.exa.ai ;;
    *)
      printf '%s\n' github.com api.github.com raw.githubusercontent.com \
        objects.githubusercontent.com \
        pypi.org files.pythonhosted.org \
        registry.npmjs.org npmjs.org \
        api.search.brave.com api.tavily.com api.exa.ai ;;
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

# ── Conectores remotos oficiais (vendor-hosted, OAuth) ──────────────────────
# Cada URL foi verificada: responde 401 (existe, pede OAuth) e serve
# /.well-known/oauth-protected-resource ou /.well-known/oauth-authorization-server,
# que é o que o app exige para registrar o cliente e abrir o navegador.
#
# São os substitutos reais dos conectores "Made by Anthropic", que só existem na
# infraestrutura da Anthropic. Estes rodam no host do próprio fornecedor e ficam
# acessíveis em 3P. Nenhum precisa de chave: o usuário clica Connect e o app faz
# o fluxo OAuth no navegador.
DESKTOP_REMOTOS="linear|Linear|https://mcp.linear.app/mcp|http
notion|Notion|https://mcp.notion.com/mcp|http
sentry|Sentry|https://mcp.sentry.dev/mcp|http
atlassian|Atlassian|https://mcp.atlassian.com/v1/mcp|http
stripe|Stripe|https://mcp.stripe.com|http
asana|Asana|https://mcp.asana.com/sse|sse"

desktop_remotos_lista() { # → "chave|Nome" por linha
  printf '%s\n' "$DESKTOP_REMOTOS" | awk -F'|' '{print $1"|"$2}'
}

desktop_mcp_remoto() { # SELECAO (chaves separadas por vírgula) → array JSON
  local sel=",$(printf '%s' "${1:-}" | tr -d ' ')," out="" sep="" k n u t
  [ "$sel" = ",," ] && { printf '[]'; return 0; }
  while IFS='|' read -r k n u t; do
    [ -z "$k" ] && continue
    case "$sel" in
      *",$k,"*)
        out="$out$sep{\"name\":\"$n\",\"transport\":\"$t\",\"url\":\"$u\",\"oauth\":true}"
        sep=","
        ;;
    esac
  done <<EOF
$DESKTOP_REMOTOS
EOF
  printf '[%s]' "$out"
}

# ── Diretório de plugins de organização ─────────────────────────────────────
org_plugins_dir() {
  if [ "$(uname -s)" = Darwin ]; then
    printf '/Library/Application Support/Claude/org-plugins'
  else
    printf '/opt/claude/org-plugins'
  fi
}

# ── Perfil de configuração gerenciada (MDM) ─────────────────────────────────
# A Anthropic publica dois templates do mesmo esquema, para os dois canais de
# política do sistema:
#   Windows: Claude.admx + Claude.adml → registro SOFTWARE\Policies\Claude
#   macOS:   com.anthropic.claudefordesktop.plist (formato pfm_/MDM)
# Verifiquei que os dois expõem exatamente as mesmas 157 chaves.
#
# No macOS o app lê, a cada abertura, por addon nativo:
#   /Library/Managed Preferences/com.anthropic.claudefordesktop.plist      (máquina)
#   /Library/Managed Preferences/<usuário>/com.anthropic.claudefordesktop.plist
#
# Por que este canal e não o configLibrary: é o caminho documentado, tem
# precedência sobre a configuração local e sobrevive a atualização do app. O
# configLibrary é formato interno — descoberto lendo o asar, sem compromisso de
# estabilidade.
#
# Valores compostos vão como string com JSON dentro: o template os declara
# type=string e o app faz JSON.parse (função ZFe no bundle), então o mesmo JSON
# que já montamos serve. Conferido no binário.

# desktop_managed_json → o documento que vai dentro do plist, em JSON.
# Chama cd_config_json_completo e remove o que não pertence ao canal gerenciado.
#
# Implementado em Python de propósito: o plist é gravado por Python (plistlib),
# então o filtro não deve depender de qual JSON_TOOL a máquina escolheu. Com
# node -e fixo, o backend python3 quebrava ao gerar o perfil.
desktop_managed_json() {
  local cfg
  cfg=$(cd_config_json_completo) || return 1
  case "$cfg" in *'"inferenceModels"'*) ;; *) return 1;; esac
  CLI_CFG="$cfg" python3 - <<'PY'
import json,os,sys
d=json.loads(os.environ["CLI_CFG"])
# desktopHome substitui as duas chaves de aba, que estão depreciadas no app.
d.pop("chatTabEnabled",None); d.pop("coworkTabEnabled",None)
d.setdefault("desktopHome","standard")
# Só as chaves que o template da Anthropic declara.
permitidas={
 "inferenceProvider","inferenceCredentialKind","inferenceGatewayBaseUrl",
 "inferenceGatewayApiKey","inferenceGatewayAuthScheme","inferenceCustomHeaders",
 "inferenceSessionLifetimeSec","inferenceStreamIdleTimeoutSec","inferenceModels",
 "modelDiscoveryEnabled","modelCatalogEnabled","modelPrefer1mContext",
 "allowedPluginMarketplaces","managedMcpServers","deploymentMode",
 "coworkEgressAllowedHosts","disableBundledSkills","skillCreationEnabled",
 "skillScanningEnabled","userPluginMarketplacesEnabled","userPluginUploadsEnabled",
 "isClaudeCodeForDesktopEnabled","isLocalDevMcpEnabled",
 "mcpPersistentAlwaysAllowEnabled","projectsEnabled","scheduledTasksEnabled",
 "keepAwakeEnabled","builtinBrowserEnabled","quickEntryScreenshotsEnabled",
 "quickEntryFileSharingEnabled","autoModeEnabled","desktopHome",
 "disableDeploymentModeChooser","allowedWorkspaceFolders",
}
out={k:v for k,v in d.items() if k in permitidas}
sys.stdout.write(json.dumps(out,ensure_ascii=False))
PY
}

# desktop_plist_gerar → imprime o perfil .plist completo (XML) no stdout.
# Estrutura conforme o template: cabeçalho Payload* + uma chave por política.
#
# Tipos seguem o template, e isso importa: inferenceModels, managedMcpServers,
# allowedPluginMarketplaces e coworkEgressAllowedHosts são declarados
# type=string nele. Vão como JSON em texto, não como estrutura nativa. O app lê
# o plist por addon nativo (readPlistValue), que devolve o tipo gravado, e a
# conversão (CVe/ZFe) só faz JSON.parse quando o schema não é string — para
# essas chaves o texto é lido cru e parseado depois. Gravar array aqui
# quebraria o contrato do template.
PLIST_TEXTO_JSON="inferenceModels managedMcpServers allowedPluginMarketplaces coworkEgressAllowedHosts inferenceCustomHeaders"
desktop_plist_gerar() {
  local json uuid
  json=$(desktop_managed_json) || return 1
  uuid=$(uuidgen 2>/dev/null | tr 'A-Z' 'a-z')
  [ -n "$uuid" ] || uuid="00000000-0000-4000-8000-000000000000"
  DESKTOP_MANAGED_JSON="$json" PLIST_UUID="$uuid" PLIST_TEXTO_JSON="$PLIST_TEXTO_JSON" python3 - <<'PY'
import json,os,plistlib,sys
dados=json.loads(os.environ["DESKTOP_MANAGED_JSON"])
como_texto={k for k in os.environ.get("PLIST_TEXTO_JSON","").split() if k}

payload={
    "PayloadType": "com.anthropic.claudefordesktop",
    "PayloadIdentifier": "com.anthropic.claudefordesktop",
    "PayloadUUID": os.environ["PLIST_UUID"],
    "PayloadVersion": 1,
    "PayloadDisplayName": "Claude",
    "PayloadDescription": "Configuração do Claude Desktop para o gateway",
    "PayloadOrganization": "Kodeo",
}
for k,v in dados.items():
    # As chaves que o template declara como string levam JSON serializado.
    if k in como_texto and not isinstance(v,str):
        v=json.dumps(v,ensure_ascii=False,separators=(",",":"))
    payload[k]=v

sys.stdout.buffer.write(plistlib.dumps(payload, fmt=plistlib.FMT_XML, sort_keys=False))
PY
}

# cd_politica → grava o perfil gerenciado. Precisa de root.
# Devolve 0 quando aplica, e 0 também quando só deixa o arquivo pronto: faltar
# privilégio não é defeito do que foi gerado, e o instalador não deve marcar
# falha por isso. A mensagem diz o comando exato para o usuário concluir.
cd_politica() {
  local alvo="/Library/Managed Preferences/com.anthropic.claudefordesktop.plist"
  local tmp; tmp="${TMPDIR:-/tmp}/claude-managed.$$.plist"
  desktop_plist_gerar >"$tmp" || { echo "falha ao gerar o perfil"; return 1; }
  plutil -lint "$tmp" >/dev/null 2>&1 || { echo "perfil inválido"; rm -f "$tmp"; return 1; }

  if [ "$(id -u)" -eq 0 ]; then
    mkdir -p "/Library/Managed Preferences"
    ( umask 022; cat "$tmp" >"$alvo" ) && chown root:wheel "$alvo" && chmod 644 "$alvo"
    local rc=$?
    rm -f "$tmp"
    [ $rc -eq 0 ] && { echo "perfil gravado em $alvo"; return 0; }
    echo "não consegui gravar em $alvo"; return 1
  fi

  # Sem root: deixa pronto e explica. O arquivo é do usuário, sem risco.
  local destino="$HOME/.claude-desktop-kodeo.plist"
  cp "$tmp" "$destino" 2>/dev/null || { rm -f "$tmp"; return 1; }
  rm -f "$tmp"
  printf '%s\n' \
    "perfil pronto em $destino" \
    "para aplicar, rode com a senha do administrador:" \
    "  sudo mkdir -p \"/Library/Managed Preferences\"" \
    "  sudo cp \"$destino\" \"$alvo\"" \
    "  sudo chown root:wheel \"$alvo\" && sudo chmod 644 \"$alvo\"" \
    "depois feche e abra o Claude"
  return 0
}

# cd_politica_remover → tira o perfil. Sem root, avisa o comando e não falha.
cd_politica_remover() {
  local alvo="/Library/Managed Preferences/com.anthropic.claudefordesktop.plist"
  local pronto="$HOME/.claude-desktop-kodeo.plist"
  rm -f "$pronto" 2>/dev/null || true
  [ -f "$alvo" ] || return 0
  if [ "$(id -u)" -eq 0 ]; then
    rm -f "$alvo" && echo "perfil removido de $alvo" && return 0
    echo "não consegui remover $alvo"; return 1
  fi
  printf '%s\n' "para remover, rode com a senha do administrador:" "  sudo rm -f \"$alvo\""
  return 0
}

# ── Plugins: instalação efetiva ─────────────────────────────────────────────
# Declarar o marketplace em allowedPluginMarketplaces só o clona. Um plugin só
# aparece na interface quando existe o registro de instalação: uma entrada em
# cowork_plugins/installed_plugins.json e a chave ligada em cowork_settings.json.
# Nada no app escreve isso por fora da interface — daí um marketplace clonado
# com "0 enabled local plugins (0 installed)".
#
# Caminho: <userData>/local-agent-mode-sessions/<conta>/<org>/cowork_plugins/
# O app aceita scope "user" (o enum é user|local|project) e confere que
# installPath está dentro de marketplaces/<nome>/.
#
# Os plugins listados abaixo têm "source" como caminho relativo no
# marketplace.json — a forma que o host instala. Os que usam git-subdir/url são
# remotos e o app os exclui de propósito, então não entram aqui.
DESKTOP_PLUGINS="code-review commit-commands hookify feature-dev plugin-dev
pr-review-toolkit security-guidance ralph-loop agent-sdk-dev claude-code-setup
claude-md-management code-simplifier explanatory-output-style
learning-output-style"

# desktop_sessoes_dir → imprime o diretório <conta>/<org> das sessões locais
desktop_sessoes_dir() {
  local base; base="$(pasta_3p)/local-agent-mode-sessions"
  [ -d "$base" ] || return 1
  # O layout é <uuid-conta>/<uuid-org>. Escolhe o que já tem cowork_plugins e,
  # entre vários, o mais recente; sem nenhum, o primeiro que parecer conta.
  local d
  d=$(find "$base" -maxdepth 2 -type d -name cowork_plugins 2>/dev/null \
      | while read -r p; do printf '%s\t%s\n' "$(stat -f %m "$p" 2>/dev/null || stat -c %Y "$p" 2>/dev/null)" "$(dirname "$p")"; done \
      | sort -rn | head -1 | cut -f2-)
  [ -n "$d" ] && { printf '%s' "$d"; return 0; }
  d=$(find "$base" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | head -1)
  [ -n "$d" ] && { printf '%s' "$d"; return 0; }
  return 1
}

# cd_plugins → instala o registro dos plugins padrão no perfil 3P.
# Idempotente: preserva o que já existe e só acrescenta o que falta.
cd_plugins() {
  local sess; sess=$(desktop_sessoes_dir) || return 0
  local mkt_dir="$sess/cowork_plugins/marketplaces"
  [ -d "$mkt_dir" ] || return 0
  local lista="${DESKTOP_PLUGINS:-}"
  [ -n "$lista" ] || return 0
  DESKTOP_PLUGINS_ALVO="$lista" CLI_SESS="$sess" CLI_TOOL="$JSON_TOOL" python3 - <<'PY'
import json,os,sys
sess=os.environ["CLI_SESS"]
alvo=os.environ["DESKTOP_PLUGINS_ALVO"].split()
mkt_root=os.path.join(sess,"cowork_plugins","marketplaces")
reg=os.path.join(sess,"cowork_plugins","installed_plugins.json")
cfg=os.path.join(sess,"cowork_settings.json")

# índice: nome do plugin -> (marketplace, caminho do marketplace, skills[])
idx={}
if os.path.isdir(mkt_root):
    for mkt in sorted(os.listdir(mkt_root)):
        mj=os.path.join(mkt_root,mkt,".claude-plugin","marketplace.json")
        try: d=json.load(open(mj,encoding="utf-8"))
        except Exception: continue
        for p in d.get("plugins") or []:
            n=p.get("name"); s=p.get("source")
            # só a forma relativa é instalável pelo host
            if not n or not isinstance(s,str): continue
            if n in idx: continue
            idx[n]=(mkt,os.path.join(mkt_root,mkt),p.get("skills") or [])

# lê o que existe sem estragar
def ler(p,padrao):
    try:
        with open(p,encoding="utf-8") as f: d=json.load(f)
        return d if isinstance(d,dict) else padrao
    except Exception:
        return padrao

instalados=ler(reg,{"plugins":{}})
if not isinstance(instalados.get("plugins"),dict): instalados["plugins"]={}
ligados=ler(cfg,{"enabledPlugins":{}})
if not isinstance(ligados.get("enabledPlugins"),dict): ligados["enabledPlugins"]={}

novos=0; faltando=[]
for nome in alvo:
    if nome not in idx: faltando.append(nome); continue
    mkt,path,skills=idx[nome]
    pid=f"{nome}@{mkt}"
    if pid in instalados["plugins"]: continue
    ent={"id":pid,"name":nome,"installPath":path,"scope":"user","enabled":True,
         "marketplaceName":mkt,"installationPreference":"available"}
    if skills: ent["skills"]=list(skills)
    instalados["plugins"][pid]=[ent]
    ligados["enabledPlugins"][pid]=True
    novos+=1

os.makedirs(os.path.dirname(reg),exist_ok=True)
with open(reg,"w",encoding="utf-8") as f: json.dump(instalados,f,indent=2,ensure_ascii=False)
with open(cfg,"w",encoding="utf-8") as f: json.dump(ligados,f,indent=2,ensure_ascii=False)

tot=len(instalados["plugins"])
print(f"plugins={tot} novos={novos}"+(f" ausentes_no_marketplace={','.join(faltando)}" if faltando else ""))
PY
}

# cd_plugins_remover → desfaz só os plugins que este instalador registrou.
# Não toca em plugin que o usuário instalou pela interface: a lista é fechada
# (DESKTOP_PLUGINS) e só remove ids cujo marketplace é um dos nossos.
cd_plugins_remover() {
  local sess; sess=$(desktop_sessoes_dir) || return 0
  [ -d "$sess/cowork_plugins" ] || return 0
  CLI_SESS="$sess" CLI_MKTS="$SKILLS_NAME,$CODE_NAME" python3 - <<'PY'
import json,os
sess=os.environ["CLI_SESS"]
nossos=set(x for x in os.environ["CLI_MKTS"].split(",") if x)
reg=os.path.join(sess,"cowork_plugins","installed_plugins.json")
cfg=os.path.join(sess,"cowork_settings.json")

def ler(p,padrao):
    try:
        with open(p,encoding="utf-8") as f: d=json.load(f)
        return d if isinstance(d,dict) else padrao
    except Exception:
        return padrao

instalados=ler(reg,{"plugins":{}})
plugins=instalados.get("plugins")
if not isinstance(plugins,dict): raise SystemExit(0)

# id no formato nome@marketplace
def nosso(pid):
    return "@" in pid and pid.rsplit("@",1)[1] in nossos

antes=len(plugins)
plugins={k:v for k,v in plugins.items() if not nosso(k)}
if len(plugins)==antes: raise SystemExit(0)

instalados["plugins"]=plugins
with open(reg,"w",encoding="utf-8") as f: json.dump(instalados,f,indent=2,ensure_ascii=False)

ligados=ler(cfg,{"enabledPlugins":{}})
ep=ligados.get("enabledPlugins")
if isinstance(ep,dict):
    ligados["enabledPlugins"]={k:v for k,v in ep.items() if not nosso(k)}
    with open(cfg,"w",encoding="utf-8") as f: json.dump(ligados,f,indent=2,ensure_ascii=False)
print("removidos:",antes-len(plugins))
PY
}

# ── MCP local via npx ───────────────────────────────────────────────────────
# A doc exige que "command" seja caminho ABSOLUTO do executável. npx resolve
# isso, mas o pacote só está disponível depois do primeiro download. Por isso
# pré-aquecemos: npx -y <pacote> --version (ou --help) baixa para o cache do
# npm, e aí o app encontra o pacote já em disco quando for conectar.
# Só incluímos o servidor cujo pacote baixou de verdade. Sem isso o app
# mostraria erro de conexão em vez de funcionar.

# npx_preaquecer PACOTE [COMANDO] → 0 se o pacote está utilizável
# Antes esta função respondia "sim" só porque _npx existia, o que é verdade para
# qualquer pacote já alguma vez corrido — até para um nome inexistente. Quem
# decide é o binário: se COMANDO é dado, ele precisa resolver em disco.
npx_preaquecer() {
  local pacote="$1" cmd="${2:-}"
  command -v npx >/dev/null 2>&1 || return 1
  if [ -n "$cmd" ] && npx_binario "$pacote" "$cmd" >/dev/null 2>&1; then return 0; fi
  npm ls -g --depth=0 "$pacote" >/dev/null 2>&1 && return 0
  # --help sai não-zero em alguns pacotes; o que interessa é o download.
  timeout 120 npx -y "$pacote" --help >/dev/null 2>&1 || true
  if [ -n "$cmd" ]; then
    npx_binario "$pacote" "$cmd" >/dev/null 2>&1 && return 0
    return 1
  fi
  npm cache ls "$pacote" 2>/dev/null | grep -q . && return 0
  ls "$HOME/.npm/_npx" >/dev/null 2>&1 && return 0
  return 1
}

# npx_caminho PACOTE COMANDO → caminho absoluto do binário dentro do cache do npm.
# Prefere o binário de _npx/<hash>/node_modules/.bin/.
# Confere que o binário veio do pacote pedido: o cache guarda todos os pacotes
# que já passaram por npx, e um .bin/ de outro pacote poderia ter o mesmo nome.
npx_binario() {
  local pacote="$1" bin="$2" p d
  for p in "$HOME/.npm/_npx"/*/node_modules/.bin/"$bin"; do
    [ -x "$p" ] || continue
    d=$(dirname "$(dirname "$p")")            # …/node_modules
    [ -d "$d/$pacote" ] && { printf '%s' "$p"; return 0; }
  done
  # global
  command -v "$bin" >/dev/null 2>&1 && { command -v "$bin"; return 0; }
  return 1
}

# desktop_mcp_local DIRETORIOS → array JSON de servidores stdio locais reais.
# Só entram os que resolvem para um binário absoluto existente.
# Sem pastas, o Filesystem não entra (não teria o que servir), mas Memory e
# Sequential Thinking continuam: eles não dependem de pasta alguma. Era isso que
# a tela prometia e o código não fazia — a tela dizia "Sem pastas, só Memory e
# Sequential Thinking entram" e a função devolvia [] antes de chegar neles.
desktop_mcp_local() { # DIRETORIOS (separados por vírgula; vazio = só Memory/Sequential)
  local dirs="${1:-}" out="" sep="" bin

  if [ -n "$dirs" ] && npx_preaquecer "@modelcontextprotocol/server-filesystem" mcp-server-filesystem; then
    bin=$(npx_binario "@modelcontextprotocol/server-filesystem" mcp-server-filesystem)
    if [ -n "$bin" ]; then
      local argsjson="" d
      for d in $(printf '%s' "$dirs" | tr ',' ' '); do
        [ -z "$d" ] && continue
        argsjson="$argsjson${argsjson:+,}\"$d\""
      done
      out="$out$sep{\"name\":\"Filesystem\",\"transport\":\"stdio\",\"command\":\"$bin\",\"args\":[${argsjson:-$HOME}],\"toolPolicy\":{\"write_file\":\"ask\",\"delete_file\":\"ask\"}}"
      sep=","
    fi
  fi

  if npx_preaquecer "@modelcontextprotocol/server-memory" mcp-server-memory; then
    bin=$(npx_binario "@modelcontextprotocol/server-memory" mcp-server-memory)
    [ -n "$bin" ] && { out="$out$sep{\"name\":\"Memory\",\"transport\":\"stdio\",\"command\":\"$bin\",\"args\":[]}"; sep=","; }
  fi

  if npx_preaquecer "@modelcontextprotocol/server-sequential-thinking" mcp-server-sequential-thinking; then
    bin=$(npx_binario "@modelcontextprotocol/server-sequential-thinking" mcp-server-sequential-thinking)
    [ -n "$bin" ] && { out="$out$sep{\"name\":\"Sequential Thinking\",\"transport\":\"stdio\",\"command\":\"$bin\",\"args\":[]}"; sep=","; }
  fi

  printf '[%s]' "$out"
}