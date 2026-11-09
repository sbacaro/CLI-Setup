#!/usr/bin/env bash
# CLI Setup — configurador de terminal (macOS / Linux)
# https://github.com/sbacaro/CLI-Setup
#
#   comando (com a chave, pula a tela da chave):
#     curl -fsSL https://raw.githubusercontent.com/sbacaro/CLI-Setup/main/instalar.sh | CLI_KEY="ck_…" bash
#   sem a chave (o configurador pede no passo 1):
#     curl -fsSL https://raw.githubusercontent.com/sbacaro/CLI-Setup/main/instalar.sh | bash
#   opções:
#     CLI_LINHAS=30 CLI_COLS=90 - Override dimensões do terminal
#
# O que ele faz: valida a chave na API, lê o catálogo de modelos do SEU plano e
# configura Claude Code, Claude Desktop, OpenCode e Codex/ChatGPT Desktop com os
# modelos que o plano realmente tem — sem lista fixa e sem redirecionar modelo.
#
# Desfazer: rode de novo e marque o que está "configurado".
# Compatível com o bash 3.2 do macOS.
#
# FASE 4: Claude Desktop completo com MCP, skills e plugins
set -u

VERSAO="2.2"
BASE="${CLI_BASE:-https://api.kodeo.com.br}"
NOME="CLI SETUP"
MARCA_INI="# >>> kodeo >>>"; MARCA_FIM="# <<< kodeo <<<"

# ── MCP Servers Habilitados ─────────────────────────────────────────────────

# ── estilo ─────────────────────────────────────────────────────────────────
E=$'\033'
R="$E[0m"; B="$E[1m"; W="$E[97m"; G="$E[38;2;122;126;136m"
OK="$E[32m"; ERR="$E[31m"; WARN="$E[33m"
ACC_F="$E[38;2;126;206;255m"
tinta() { local t="$1"; printf '%s[38;2;%d;%d;%dm' "$E" $(( t*62/100 )) $(( t*86/100 )) "$t"; }
cursor_off() { printf '%s[?25l' "$E"; }
cursor_on()  { printf '%s[?25h' "$E"; }
limpa_linha() { printf '\r%s[2K' "$E"; }
TTY=/dev/tty; [ -r "$TTY" ] || TTY=/dev/stdin
# O assistente é interativo: sem terminal não há como perguntar nada. A guarda
# fica antes de qualquer leitura de /dev/tty, senão o bash reclama no caminho.
exige_terminal() {
  [ -r "$TTY" ] && [ -t 1 ] && return 0
  printf '\n  Este configurador precisa de um terminal interativo.\n'
  printf '  Rode o comando direto no Terminal, sem redirecionar a saída.\n\n'
  exit 1
}
exige_terminal
# Medir o terminal. `tput`/`stty` sem redirecionamento leem o stdin, que é um pipe
# quando o comando é "curl … | bash" — e aí respondem 80x24 mesmo numa janela grande.
# Por isso a leitura vai pelo tty de verdade.
medir_terminal() {
  local sz=""
  sz=$(stty size <"$TTY" 2>/dev/null) || sz=""
  case "$sz" in
    [0-9]*' '[0-9]*) LINHAS=${sz%% *}; COLS=${sz##* } ;;
    *) LINHAS=$(tput -T"${TERM:-xterm}" lines 2>/dev/null || echo 24)
       COLS=$(tput -T"${TERM:-xterm}" cols 2>/dev/null || echo 80) ;;
  esac
  case "$LINHAS" in ''|*[!0-9]*|0) LINHAS=24;; esac
  case "$COLS" in ''|*[!0-9]*|0) COLS=80;; esac
  [ "$LINHAS" -lt 14 ] && LINHAS=14
  [ "$COLS" -lt 44 ] && COLS=44
  # override para testar um tamanho específico sem redimensionar a janela
  case "${CLI_LINHAS:-}" in ''|*[!0-9]*) ;; *) LINHAS=$CLI_LINHAS ;; esac
  case "${CLI_COLS:-}"   in ''|*[!0-9]*) ;; *) COLS=$CLI_COLS ;; esac
}
medir_terminal
# Largura do bloco: no máximo 76 colunas, e nunca mais do que a janela.
LARG=$COLS; [ "$LARG" -gt 76 ] && LARG=76
# A coluna de etapas fica encostada à direita do bloco. Quando ela cabe, o bloco
# não é centralizado sozinho: o conjunto bloco+etapas é que fica no meio da tela,
# senão a tela parece torta (bloco no meio, etapas coladas na borda).
ETAPAS_LARG=16
if [ "$COLS" -ge $((LARG+ETAPAS_LARG+4)) ]; then
  MARGEM=$(( (COLS - (LARG+ETAPAS_LARG)) / 2 )); [ "$MARGEM" -lt 2 ] && MARGEM=2
else
  MARGEM=$(( (COLS - LARG) / 2 )); [ "$MARGEM" -lt 0 ] && MARGEM=0
fi
ESPACO=$(printf '%*s' "$MARGEM" '')
tracos() { local i s=""; for ((i=0; i<$1; i++)); do s="${s}─"; done; printf '%s' "$s"; }
regua() { tracos $((LARG-4)); }

restaura() { cursor_on; stty echo 2>/dev/null <"$TTY" || true; printf '%s' "$R"; }
cancela() { restaura; printf '\n\n  %sCancelado.%s Nada foi alterado.\n\n' "$G" "$R"; exit 130; }
trap restaura EXIT
trap cancela INT TERM
pausa() { sleep "$1"; }
digita() { local s="$1" i; for ((i=0; i<${#s}; i++)); do printf '%s' "${s:$i:1}"; sleep 0.006; done; }
tecla() {
  local ch seq
  IFS= read -rsn1 ch <"$TTY" || { printf 'eof'; return; }
  case "$ch" in
    $'\x1b') IFS= read -rsn2 -t 1 seq <"$TTY" 2>/dev/null || seq=""
      case "$seq" in '[A') printf 'up';; '[B') printf 'down';; '[D') printf 'left';; '[C') printf 'right';; *) printf 'esc';; esac ;;
    ''|$'\n'|$'\r') printf 'enter';; ' ') printf 'space';; $'\x7f'|$'\b') printf 'bs';; $'\x03') cancela;;
    *) printf '%s' "$ch";;
  esac
}

# ── logotipo ───────────────────────────────────────────────────────────────
LOGO_CLI=(
' ██████╗  ██╗        ██╗'
'██╔════╝  ██║        ██║'
'██║        ██║        ██║'
'██║        ██║        ██║'
'╚██████╗   ███████╗   ██║'
' ╚═════╝   ╚══════╝   ╚═╝'
)
LOGO_SETUP=(
'███████╗  ███████╗  ████████╗  ██╗   ██╗  ██████╗'
'██╔════╝  ██╔════╝  ╚══██╔══╝  ██║   ██║  ██╔══██╗'
'███████╗  █████╗       ██║     ██║   ██║  ██████╔╝'
'╚════██║  ██╔══╝       ██║     ██║   ██║  ██╔═══╝'
'███████║  ███████╗     ██║     ╚██████╔╝  ██║'
'╚══════╝  ╚══════╝     ╚═╝      ╚═════╝   ╚═╝'
)
logo_linha() { if [ "$1" -lt 6 ]; then printf '%s' "${LOGO_CLI[$1]}"; else printf '%s' "${LOGO_SETUP[$(( $1 - 6 ))]}"; fi; }
logo_tom() {
  local i="$1" s="$2" t d
  t=$(( 236 - i * 9 )); [ "$t" -lt 132 ] && t=132
  if [ "$s" -ge 0 ]; then
    d=$(( i - s )); [ "$d" -lt 0 ] && d=$(( 0 - d ))
    case "$d" in 0) t=255;; 1) t=$((t+52));; 2) t=$((t+26));; esac
    [ "$t" -gt 255 ] && t=255
  fi
  printf '%s' "$t"
}

# ── abertura ───────────────────────────────────────────────────────────────
abertura() {
  printf '%s[2J%s[H' "$E" "$E"; cursor_off
  local i s col topo
  local LOGO_LARG=52
  # o logo é centralizado na mesma coluna do bloco das outras telas
  col=$(( MARGEM + (LARG - LOGO_LARG) / 2 )); [ "$col" -lt 2 ] && col=2
  topo=$(( (LINHAS - 15) / 2 )); [ "$topo" -lt 2 ] && topo=2
  if [ "$COLS" -lt 58 ] || [ "$LINHAS" -lt 20 ]; then
    printf '%s[H\n' "$E"
    printf '%s  %s%sCLI SETUP%s  %sConfigurador%s\n' "$ESPACO" "$B" "$ACC_F" "$R" "$G" "$R"
    pausa 0.3
  else
    # linhas surgem de cima para baixo
    for ((i=0; i<12; i++)); do
      printf '%s[%d;%dH%s%s%s' "$E" $((topo+i)) "$col" "$(tinta "$(logo_tom "$i" -1)")" "$(logo_linha "$i")" "$R"
      pausa 0.04
    done
    # o brilho atravessa duas vezes, a segunda mais rápida
    for ((s=-2; s<14; s++)); do
      for ((i=0; i<12; i++)); do
        printf '%s[%d;%dH%s%s%s' "$E" $((topo+i)) "$col" "$(tinta "$(logo_tom "$i" "$s")")" "$(logo_linha "$i")" "$R"
      done
      pausa 0.03
    done
    for ((s=-4; s<14; s++)); do
      for ((i=0; i<12; i++)); do
        printf '%s[%d;%dH%s%s%s' "$E" $((topo+i)) "$col" "$(tinta "$(logo_tom "$i" "$s")")" "$(logo_linha "$i")" "$R"
      done
      pausa 0.016
    done
  fi
  # assinatura: mesma largura do logo, para ficar alinhada com ele
  local sub="Configurador de terminal  ·  api.kodeo.com.br  ·  v$VERSAO"
  local lin_sub
  if [ "$LINHAS" -lt 20 ] || [ "$COLS" -lt 58 ]; then lin_sub=3; col=2; else lin_sub=$((topo+13)); fi
  printf '%s[%d;%dH%s' "$E" "$lin_sub" "$col" "$G"; digita "$sub"; printf '%s' "$R"
  pausa 0.4
}

# ── moldura das telas ──────────────────────────────────────────────────────
TOTAL=4
ETAPA=0
etapas() {
  # a coluna encosta no bloco, não flutua no fim da tela
  local col=$((MARGEM+LARG+3)) i marca
  [ "$COLS" -ge $((col+ETAPAS_LARG)) ] || return 0
  printf '%s[3;%dH%sEtapas%s' "$E" "$col" "$G" "$R"
  for i in 1 2 3 4; do
    case "$i" in 1) marca="Chave";; 2) marca="Ferramentas";; 3) marca="Modelos";; 4) marca="Aplicar";; esac
    if [ "$i" -lt "$ETAPA" ]; then
      printf '%s[%d;%dH%s✓%s %s%s%s' "$E" $((3+i)) "$col" "$OK" "$R" "$G" "$marca" "$R"
    elif [ "$i" -eq "$ETAPA" ]; then
      printf '%s[%d;%dH%s▸%s %s%s%s' "$E" $((3+i)) "$col" "$ACC_F" "$R" "$W" "$marca" "$R"
    else
      printf '%s[%d;%dH%s·%s %s%s%s' "$E" $((3+i)) "$col" "$G" "$R" "$G" "$marca" "$R"
    fi
  done
}
# linha TEXTO — imprime uma linha do corpo já com a margem
linha() { printf '%s  %s\n' "$ESPACO" "$*"; }
tela() { # "1/4  Chave" [etapa]
  local dir="$1" pad
  ETAPA="${2:-$ETAPA}"
  pad=$((LARG-2-23-${#dir})); [ "$pad" -lt 1 ] && pad=1
  printf '%s[2J%s[H' "$E" "$E"
  etapas
  printf '%s[H\n' "$E"
  printf '%s  %s%s%s%s  %s%s%s%*s%s%s%s\n' "$ESPACO" "$B" "$ACC_F" "$NOME" "$R" "$G" "Configurador" "$R" "$pad" '' "$G" "$dir" "$R"
  printf '%s  %s%s%s\n\n' "$ESPACO" "$G" "$(regua)" "$R"
}
dicas() {
  local d s="" sep=""
  for d in "$@"; do s="$s$sep${B}${W}${d%%:*}${R} ${G}${d#*:}${R}"; sep="   "; done
  printf '%s' "$s"
}
rodape() {
  local texto; texto=$(dicas "$@")
  if [ "$LINHAS" -ge 18 ]; then
    printf '%s7' "$E"; printf '%s[%d;1H' "$E" $((LINHAS-2))
    printf '%s  %s%s%s\n%s  %s' "$ESPACO" "$G" "$(regua)" "$R" "$ESPACO" "$texto"
    printf '%s8' "$E"
  else
    printf '\n%s  %s%s%s\n%s  %s\n' "$ESPACO" "$G" "$(regua)" "$R" "$ESPACO" "$texto"
  fi
}
# As três partes da caixa têm a mesma largura visível (LARG colunas, contando a
# margem), então a borda direita fecha. A conta está em cada função.
caixa_topo()  {
  # ╭─(2) espaço(1) título(T) espaço(1) traços(D) ╮(1) = 5+T+D = LARG
  local t="$1" D; D=$(( LARG - 7 - ${#t} )); [ "$D" -lt 1 ] && D=1
  printf '%s  %s╭─%s %s%s%s%s %s%s%s╮%s\n' "$ESPACO" "$G" "$R" "$B" "$ACC_F" "$t" "$R" "$G" "$(tracos "$D")" "$R"
}
caixa_linha() {
  # │(1) 2 espaços conteúdo(C) preenchimento(P) │(1) = 4+C+P = LARG
  # O preenchimento é montado com repetição de espaço: %*s com string vazia muda
  # de comportamento entre o bash 3.2 do macOS e versões novas.
  local vis="$2" P; P=$(( LARG - 6 - vis )); [ "$P" -lt 0 ] && P=0
  local espaco=""; local j
  for ((j=0;j<P;j++)); do espaco="$espaco "; done
  printf '%s  %s│%s  %s%s%s│%s\n' "$ESPACO" "$G" "$R" "$1" "$espaco" "$G" "$R"
}
caixa_fundo() {
  # ╰(1) traços(D) ╯(1) = 2+D = LARG, igual à largura do topo
  local D; D=$(( LARG - 4 )); [ "$D" -lt 1 ] && D=1
  printf '%s  %s╰%s╯%s\n' "$ESPACO" "$G" "$(tracos "$D")" "$R"
}
SPIN='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

# ── JSON: ferramenta ───────────────────────────────────────────────────────
JSON_TOOL=""
if command -v node >/dev/null 2>&1; then JSON_TOOL=node
elif command -v python3 >/dev/null 2>&1 && { [ "$(uname -s)" != Darwin ] || xcode-select -p >/dev/null 2>&1; }; then JSON_TOOL=python3; fi

# ── bibliotecas ────────────────────────────────────────────────────────────
# O comando do painel é "curl … | bash", que não tem a pasta lib/ ao lado.
# Então: usa a pasta local quando existe (desenvolvimento) e, quando não existe,
# baixa as bibliotecas do mesmo repositório numa pasta temporária.
CLI_RAW="${CLI_RAW:-https://raw.githubusercontent.com/sbacaro/CLI-Setup/main}"
CLI_DIR=""
for c in "$(dirname "$0")" "$PWD"; do
  [ -f "$c/lib/catalogo.sh" ] && { CLI_DIR="$c"; break; }
done
if [ -z "$CLI_DIR" ]; then
  CLI_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cli-setup.XXXXXX") || exit 1
  trap 'rm -rf "$CLI_DIR"' EXIT
  mkdir -p "$CLI_DIR/lib"
  ok_libs=0
  for f in json catalogo geradores opencode; do
    if curl -fsSL -m 30 "$CLI_RAW/lib/$f.sh" -o "$CLI_DIR/lib/$f.sh" 2>/dev/null; then ok_libs=$((ok_libs+1)); fi
  done
  if [ "$ok_libs" -lt 4 ]; then
    printf '\n  %s✗%s Não consegui baixar as bibliotecas de %s.\n' "$ERR" "$R" "$CLI_RAW"
    printf '    Verifique a internet, ou baixe o repositório inteiro e rode ./instalar.sh\n\n'
    exit 1
  fi
fi
. "$CLI_DIR/lib/json.sh"
. "$CLI_DIR/lib/catalogo.sh"
. "$CLI_DIR/lib/geradores.sh"
. "$CLI_DIR/lib/opencode.sh"

# ══ 1/4  CHAVE ════════════════════════════════════════════════════════════
CHAVE="${CLI_KEY:-${KODEO_KEY:-}}"
chave_ok() { case "$1" in ck_??????*) return 0;; *) return 1;; esac; }
validar_chave() { curl -s -m 20 -o /dev/null -w '%{http_code}' -A "cli-setup/$VERSAO" "$BASE/v1/me" -H "x-api-key: $1" 2>/dev/null || printf '000'; }
CHAVE_DO_COMANDO=0

tela_chave() {
  tela "1/$TOTAL  Chave" 1
  linha "${B}${W}Passo 1 de $TOTAL — a chave.${R}"
  linha ""
  linha "O configurador precisa da sua chave para ver quais modelos o seu plano tem."
  linha "Ela fica só nos arquivos de configuração das ferramentas que você marcar."
  linha "${G}Onde achar: painel da Kodeo → API → chaves (começa com ck_).${R}"
  linha ""
  rodape "enter:continuar" "backspace:apagar" "ctrl+c:sair"
  local chave="$CHAVE" k i
  cursor_on
  while :; do
    limpa_linha; printf '%s  %s❯%s ' "$ESPACO" "$ACC_F" "$R"; for ((i=0; i<${#chave}; i++)); do printf '•'; done
    k=$(tecla)
    case "$k" in
      enter)
        if ! chave_ok "$chave"; then
          printf '\n%s  %s✗%s A chave começa com ck_. Confira e tente de novo.' "$ESPACO" "$ERR" "$R"; printf '%s[1A' "$E"
        else
          local st; st=$(validar_chave "$chave")
          case "$st" in
            200) break ;;
            401|403) printf '\n%s  %s✗%s A API recusou essa chave. Confira no painel e cole de novo.' "$ESPACO" "$ERR" "$R"; printf '%s[1A' "$E" ;;
            *) printf '\n%s  %s!%s Não consegui falar com %s (%s). Verifique a internet.' "$ESPACO" "$WARN" "$R" "${BASE#https://}" "$st"; printf '%s[1A' "$E" ;;
          esac
        fi ;;
      bs) chave="${chave%?}";;
      space|up|down|left|right|esc) ;;
      eof) cancela;;
      *) chave="$chave$k";;
    esac
  done
  cursor_off
  CHAVE="$chave"
  printf '\n'; limpa_linha; printf '%s  %s✓%s Chave válida\n' "$ESPACO" "$OK" "$R"
  pausa 0.4
}

tela_chave_do_comando() {
  tela "1/$TOTAL  Chave" 1
  linha "${B}${W}Passo 1 de $TOTAL — a chave.${R}"
  linha ""
  linha "Chave recebida."
  linha ""
  local sinal="/tmp/cli-setup-$$" st i=0
  rm -f "$sinal"; ( validar_chave "$CHAVE" >"$sinal.st"; : >"$sinal" ) &
  while [ ! -e "$sinal" ]; do limpa_linha; printf '%s  %s%s%s Verificando a chave' "$ESPACO" "$ACC_F" "${SPIN:$((i%10)):1}" "$R"; sleep 0.05; i=$((i+1)); done
  st=$(cat "$sinal.st" 2>/dev/null); rm -f "$sinal" "$sinal.st"; limpa_linha
  case "$st" in
    200) printf '%s  %s✓%s Chave válida\n' "$ESPACO" "$OK" "$R"; pausa 0.5; return 0 ;;
    401|403) printf '%s  %s✗%s A API recusou a chave. Pegue o comando de novo no painel.\n' "$ESPACO" "$ERR" "$R" ;;
    *) printf '%s  %s!%s Não consegui falar com %s (%s). Verifique a internet.\n' "$ESPACO" "$WARN" "$R" "${BASE#https://}" "$st" ;;
  esac
  rodape "enter:sair"; while :; do [ "$(tecla)" = enter ] && break; done; exit 1
}

# ══ 2/4  FERRAMENTAS ══════════════════════════════════════════════════════
NOMES=("Claude Code" "Claude Desktop" "OpenCode" "Codex + ChatGPT")
IDS=("claude-code" "claude-app" "opencode" "codex")
CONF=(0 0 0 0); SEL=(0 0 0 0); INST=(0 0 0 0)

pasta_3p() {
  local d=""
  d=$(ps ax -ww -o command 2>/dev/null | grep 'Claude.app/Contents/' | grep -v -e grep -e '/bin/zsh' -e '/bin/bash' \
      | grep -- '--user-data-dir=' | head -1 | sed 's/.*--user-data-dir=//; s/ --.*$//')
  case "$d" in "$HOME"/*) ;; *) d="";; esac
  if [ -n "$d" ]; then case "$(basename "$d")" in Claude) printf '%s/Claude-3p' "$(dirname "$d")";; *) printf '%s' "$d";; esac
  elif [ "$(uname -s)" = Darwin ]; then printf '%s/Library/Application Support/Claude-3p' "$HOME"
  else printf '%s/.config/Claude-3p' "$HOME"; fi
}
CX_DIR="${CODEX_HOME:-$HOME/.codex}"; CX_CFG="$CX_DIR/config.toml"

detectar() {
  # Claude Code: verifica settings.json PRIMEIRO (fonte principal)
  if grep -qs "api.kodeo.com.br" "$HOME/.claude/settings.json" 2>/dev/null; then
    CONF[0]=1
  elif grep -qs "^# >>> kodeo >>>" "$HOME/.zshrc" "$HOME/.bashrc" 2>/dev/null; then
    # Só marca se tem vestígio E o settings.json não tem (config antiga/incompleta)
    # Ou se tem ANTHROPIC_BASE_URL no bloco do kodeo
    local bloco_encontrado=0
    for f in "$HOME/.zshrc" "$HOME/.bashrc"; do
      if [ -f "$f" ]; then
        if grep -qs "^# >>> kodeo >>>" "$f" && grep -qs "ANTHROPIC_BASE_URL" "$f" 2>/dev/null; then
          bloco_encontrado=1
          break
        fi
      fi
    done
    [ "$bloco_encontrado" -eq 1 ] && CONF[0]=1
  fi
  command -v claude >/dev/null 2>&1 && INST[0]=1
  
  # Claude Desktop: verifica configLibrary (mais confiável que o .json principal)
  local lib; lib="$(pasta_3p)/configLibrary"
  if [ -f "$lib/_meta.json" ] && grep -qs '"name": *"Kodeo"' "$lib/_meta.json" 2>/dev/null; then
    CONF[1]=1
  fi
  { [ -d "/Applications/Claude.app" ] || [ -d "$HOME/Applications/Claude.app" ]; } && INST[1]=1
  
  # OpenCode
  grep -qs '"kodeo"' "$HOME/.config/opencode/opencode.json" 2>/dev/null && CONF[2]=1
  command -v opencode >/dev/null 2>&1 && INST[2]=1
  
  # Codex / ChatGPT
  grep -qs "model_providers.kodeo" "$CX_CFG" 2>/dev/null && CONF[3]=1
  command -v codex >/dev/null 2>&1 && INST[3]=1
  
  # Se nada está configurado, marca todos para seleção
  local algum=0; for i in 0 1 2 3; do [ "${CONF[$i]}" -eq 1 ] && algum=1; done
  [ "$algum" -eq 0 ] && for i in 0 1 2 3; do SEL[$i]=1; done
}

tela_ferramentas() { # 0 = aplicar, 1 = voltar
  tela "2/$TOTAL  Ferramentas" 2
  linha "${B}${W}Passo 2 de $TOTAL — o que configurar.${R}"
  linha ""
  linha "O que já está configurado pode ser desconfigurado."
  linha "${G}Codex e ChatGPT Desktop usam o mesmo arquivo: marcar um configura os dois.${R}"
  linha ""
  local n=${#NOMES[@]} i cur=0 k
  # largura das colunas a partir do maior nome, para nada se sobrepor
  local larg_nome=0 x
  for ((i=0;i<n;i++)); do x=${#NOMES[$i]}; [ "$x" -gt "$larg_nome" ] && larg_nome=$x; done
  larg_nome=$((larg_nome+2))
  if [ "$CHAVE_DO_COMANDO" -eq 0 ]; then rodape "↑↓:mover" "espaço:marcar" "enter:continuar" "←:voltar" "ctrl+c:sair"
  else rodape "↑↓:mover" "espaço:marcar" "enter:continuar" "ctrl+c:sair"; fi
  desenha() {
    for ((i=0;i<n;i++)); do
      local pre="  " caixa estado acao nome="${NOMES[$i]}" esc
      [ "$i" -eq "$cur" ] && pre="${ACC_F}❯${R} "
      if [ "${SEL[$i]}" -eq 1 ]; then caixa="${ACC_F}[x]${R}"; else caixa="${G}[ ]${R}"; fi
      if [ "${CONF[$i]}" -eq 1 ]; then estado="${OK}configurado${R}"; acao="desconfigurar"; esc=11
      else estado="${G}não configurado${R}"; acao="configurar"; esc=15; fi
      [ "${INST[$i]}" -eq 0 ] && [ "${CONF[$i]}" -eq 0 ] && { estado="${G}não encontrado${R}"; esc=14; }
      if [ "${SEL[$i]}" -eq 1 ]; then acao="${W}→ ${acao}${R}"; else acao="${G}  ${acao}${R}"; fi
      limpa_linha; printf '%s  %s%s %s%s%*s%s%*s%s\n' "$ESPACO" "$pre" "$caixa" "$W" "$nome" $((larg_nome-${#nome})) '' "$estado" $((23-esc)) '' "$acao"
    done
  }
  desenha
  while :; do
    k=$(tecla)
    case "$k" in
      up|k) cur=$(( (cur+n-1) % n ));; down|j) cur=$(( (cur+1) % n ));;
      space) SEL[$cur]=$((1-SEL[$cur]));;
      a|A) for ((i=0;i<n;i++)); do SEL[$i]=1; done;;
      left|b|B) [ "$CHAVE_DO_COMANDO" -eq 0 ] && return 1;;
      enter) local algum=0; for ((i=0;i<n;i++)); do [ "${SEL[$i]}" -eq 1 ] && algum=1; done; [ "$algum" -eq 1 ] && return 0;;
      eof) cancela;;
    esac
    printf '%s[%dA' "$E" "$n"; desenha
  done
}

# ══ 3/4  MODELOS ══════════════════════════════════════════════════════════
# Lê o catálogo do plano e mostra o que cada ferramenta vai receber.
OPUS_ID=""; SONNET_ID=""; HAIKU_ID=""; PADRAO_ID=""; CAT_N=0; CAT_FALHOU=0

carregar_catalogo() {
  limpa_linha; printf '%s  %s%s%s Lendo os modelos do seu plano' "$ESPACO" "$ACC_F" "${SPIN:0:1}" "$R"
  local json
  json=$(curl -s -m 25 -A "cli-setup/$VERSAO" "$BASE/v1/models" -H "x-api-key: $CHAVE" 2>/dev/null)
  limpa_linha
  case "$json" in *'"data"'*) ;; *) CAT_FALHOU=1; return 1 ;; esac
  CATALOGO_JSON="$json"; CATALOGO_LIDO=1
  # /v1/models lista o catálogo inteiro (inclui planos superiores). A lista do
  # plano vem do /v1/me, campo "modelos" — é ela que filtra o que o usuário pode usar.
  cat_plano_carregar "$CHAVE" || true
  export CATALOGO_JSON CATALOGO_LIDO CAT_PLANO_IDS JSON_TOOL
  CAT_N=$(cat_contar); OPUS_ID=$(cat_melhor_tier opus)
  SONNET_ID=$(cat_melhor_tier sonnet); HAIKU_ID=$(cat_melhor_tier haiku)
  PADRAO_ID=$(cat_padrao_geral)
  cat_resumo_plano
  [ -n "$CAT_N" ] && [ "$CAT_N" -gt 0 ] || { CAT_FALHOU=1; return 1; }
  return 0
}

# cat_resumo_plano — quantos modelos o plano libera de fato, por família
cat_resumo_plano() {
  CAT_PLANO_N=0; CAT_PLANO_ANTHROPIC=0; CAT_PLANO_OPENAI=0
  [ -z "${CAT_PLANO_IDS:-}" ] && { CAT_PLANO_N=$(cat_contar); return 0; }
  local id fam
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    CAT_PLANO_N=$((CAT_PLANO_N+1))
    fam=$(cat_familia "$id")
    case "$fam" in
      anthropic) CAT_PLANO_ANTHROPIC=$((CAT_PLANO_ANTHROPIC+1)) ;;
      openai)    CAT_PLANO_OPENAI=$((CAT_PLANO_OPENAI+1)) ;;
    esac
  done <<EOF
$CAT_PLANO_IDS
EOF
  return 0
}

tela_modelos() { # 0 = seguir, 1 = voltar
  tela "3/$TOTAL  Modelos" 3
  linha "${B}${W}Passo 3 de $TOTAL — os modelos do seu plano.${R}"
  linha ""
  local k
  if ! carregar_catalogo; then
    linha "${ERR}✗${R} Não consegui ler o catálogo da API."
    linha "  A chave é válida, mas ${BASE#https://}/v1/models não respondeu."
    linha ""
    rodape "enter:tentar" "←:voltar" "ctrl+c:sair"
    while :; do k=$(tecla); case "$k" in enter) return 0;; left) return 1;; esc) return 1;; eof) cancela;; esac; done
  fi
  linha "${OK}✓${R} ${CAT_PLANO_N} modelos no seu plano"
  linha ""
  linha "${B}${W}O que cada app recebe:${R}"
  linha "  ${G}Claude Code / Desktop${R}  ${CAT_PLANO_ANTHROPIC} modelos Anthropic"
  linha "  ${G}ChatGPT / Codex${R}         ${CAT_PLANO_OPENAI} modelos OpenAI"
  linha "  ${G}OpenCode${R}                ${CAT_PLANO_N} modelos (todos)"
  linha ""
  linha "${G}Padrão para começar:${R} ${W}${PADRAO_ID}${R}"
  linha ""
  linha "${G}Modelos de planos superiores ficam de fora: o catálogo da API lista tudo,${R}"
  linha "${G}mas só os do seu plano respondem. Um deles devolveria 403.${R}"
  linha ""
  local atalhos
  atalhos=$(printf '%s' "${G}Atalhos no Claude Desktop:${R}"
    [ -n "$OPUS_ID" ]   && printf '  %s%s%s' "$W" "$OPUS_ID" "$R"
    [ -n "$SONNET_ID" ] && printf '  %s%s%s' "$W" "$SONNET_ID" "$R"
    [ -n "$HAIKU_ID" ]  && printf '  %s%s%s' "$W" "$HAIKU_ID" "$R"
    printf '%s' "${R}")
  linha "$atalhos"
  linha ""
  rodape "enter:continuar" "←:voltar" "ctrl+c:sair"
  while :; do k=$(tecla); case "$k" in enter) return 0;; left) return 1;; esc) return 1;; eof) cancela;; esac; done
}

# ══ 4/4  APLICAR ══════════════════════════════════════════════════════════
FALHAS=0
passo() { # texto, comando…
  local txt="$1"; shift
  local sinal="/tmp/cli-setup-p-$$-$RANDOM" i=0 rc
  rm -f "$sinal"; ( "$@" >"$sinal.out" 2>&1; echo $? >"$sinal.rc"; : >"$sinal" ) &
  while [ ! -e "$sinal" ]; do limpa_linha; printf '%s    %s%s%s %s' "$ESPACO" "$ACC_F" "${SPIN:$((i%10)):1}" "$R" "$txt"; sleep 0.05; i=$((i+1)); done
  rc=$(cat "$sinal.rc" 2>/dev/null || echo 1); limpa_linha
  if [ "$rc" = 0 ]; then printf '%s    %s✓%s %s\n' "$ESPACO" "$OK" "$R" "$txt"
  else
    printf '%s    %s✗%s %s %s(%s)%s\n' "$ESPACO" "$ERR" "$R" "$txt" "$G" "$(head -c 140 "$sinal.out" 2>/dev/null | tr '\n' ' ')" "$R"
    FALHAS=$((FALHAS+1))
  fi
  rm -f "$sinal" "$sinal.out" "$sinal.rc"; sleep 0.1
}

RC_FILES() { local f; for f in "$HOME/.zshrc" "$HOME/.bashrc"; do [ -f "$f" ] && printf '%s\n' "$f"; done; [ -f "$HOME/.zshrc" ] || printf '%s\n' "$HOME/.zshrc"; }
rc_remover_bloco() {
  local f="$1"; [ -f "$f" ] || return 0
  awk -v a="$MARCA_INI" -v b="$MARCA_FIM" '$0==a{d=1;next} $0==b{d=0;next} !d' "$f" >"$f.cli-tmp" && mv "$f.cli-tmp" "$f"
}
rc_escrever_bloco() { # ANTHROPIC_* do plano + KODEO_API_KEY
  local f="$1"; rc_remover_bloco "$f"
  {
    printf '%s\n' "$MARCA_INI"
    claude_code_env "$BASE" "$CHAVE" "$OPUS_ID" "$SONNET_ID" "$HAIKU_ID" \
      | while IFS= read -r l; do [ -n "$l" ] && printf 'export %s\n' "$l"; done
    printf 'export KODEO_API_KEY="%s"\n' "$CHAVE"
    printf '%s\n' "$MARCA_FIM"
  } >>"$f"
}
rc_escrever_bloco_codex() { # só a chave
  local f="$1"; grep -qs "^$MARCA_INI" "$f" 2>/dev/null && grep -qs "KODEO_API_KEY" "$f" && return 0
  rc_remover_bloco "$f"
  printf '%s\nexport KODEO_API_KEY="%s"\n%s\n' "$MARCA_INI" "$CHAVE" "$MARCA_FIM" >>"$f"
}
teste_models() { local st; st=$(curl -s -m 20 -o /dev/null -w '%{http_code}' -A "cli-setup/$VERSAO" "$BASE/v1/models" -H "x-api-key: $CHAVE"); [ "$st" = 200 ] || { echo "API respondeu $st"; return 1; }; }
teste_responses() { local st; st=$(curl -s -m 60 -o /dev/null -w '%{http_code}' -A "cli-setup/$VERSAO" "$BASE/v1/responses" -H "Authorization: Bearer $CHAVE" -H 'content-type: application/json' -d "{\"model\":\"$PADRAO_ID\",\"input\":\"Responda só: ok\",\"max_output_tokens\":20,\"store\":false}"); [ "$st" = 200 ] || { echo "API respondeu $st"; return 1; }; }

# ── Claude Code ────────────────────────────────────────────────────────────
CC_CFG="$HOME/.claude/settings.json"
cc_env_json() { # imprime o objeto env em JSON, a partir dos modelos do plano
  claude_code_env "$BASE" "$CHAVE" "$OPUS_ID" "$SONNET_ID" "$HAIKU_ID" | catalogo_env_json
}
catalogo_env_json() {
  if [ "${JSON_TOOL:-}" = node ]; then
    node -e 'let t="";process.stdin.on("data",c=>t+=c).on("end",()=>{const o={};for(const l of t.split("\n")){if(!l.trim())continue;const i=l.indexOf("=");o[l.slice(0,i)]=l.slice(i+1)}process.stdout.write(JSON.stringify({env:o}))});'
  else
    python3 -c 'import sys,json
o={}
for l in sys.stdin.read().split("\n"):
    if not l.strip(): continue
    k,_,v=l.partition("="); o[k]=v
print(json.dumps({"env":o}))'
  fi
}
aplicar_claude_code() {
  [ -n "$JSON_TOOL" ] || { printf '    %s✗%s Preciso do Node.js ou Python para editar o settings.json.\n' "$ERR" "$R"; FALHAS=$((FALHAS+1)); return; }
  local envjson; envjson=$(cc_env_json)
  passo "Variáveis e modelos do plano em ~/.claude/settings.json" json_op "$CC_CFG" merge "$envjson"
  local f; for f in $(RC_FILES); do passo "Atalhos de modelo no ${f/#$HOME/~}" rc_escrever_bloco "$f"; done
  passo "Teste de conexão" teste_models
}
remover_claude_code() {
  if [ -f "$CC_CFG" ]; then
    passo "Tirar as variáveis do ~/.claude/settings.json" json_op "$CC_CFG" del "env"
  fi
  local f; for f in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [ -f "$f" ] && grep -qs "^$MARCA_INI" "$f" || continue
    # se o Codex continua configurado, o bloco fica só com a chave dele
    if grep -qs "model_providers.kodeo" "$CX_CFG" 2>/dev/null; then
      passo "Manter só a KODEO_API_KEY em ${f/#$HOME/~}" rc_escrever_bloco_codex "$f"
    else
      passo "Remover o bloco de ${f/#$HOME/~}" rc_remover_bloco "$f"
    fi
  done
  true
}

# ── Claude Desktop ─────────────────────────────────────────────────────────
cd_config_json() { claude_desktop_json "$BASE" "$CHAVE"; }
cd_escrever() {
  local dir; dir=$(pasta_3p); local lib="$dir/configLibrary"; mkdir -p "$lib" || return 1
  # Sem catálogo, a config sairia com inferenceModels vazio e o app ignoraria tudo.
  if [ -z "$CATALOGO_JSON" ]; then echo "catálogo vazio: rode a etapa de modelos antes"; return 1; fi
  local id; id=$( (uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null) | tr 'A-Z' 'a-z')
  [ -n "$id" ] || { echo "não consegui gerar um id"; return 1; }
  # tira um config nosso anterior (só o nosso)
  if [ -f "$lib/_meta.json" ] && grep -q '"name": *"Kodeo"' "$lib/_meta.json" 2>/dev/null; then
    local ant; ant=$(grep -o '"appliedId": *"[^"]*"' "$lib/_meta.json" | sed 's/.*: *"//; s/"$//')
    [ -n "$ant" ] && rm -f "$lib/$ant.json"; rm -f "$lib/_meta.json"
  fi
  local config_json; config_json=$(cd_config_json)
  ( umask 077; printf '%s' "$config_json" >"$lib/$id.json.cli-tmp" ) && mv "$lib/$id.json.cli-tmp" "$lib/$id.json" || return 1
  ( umask 077; printf '{\n  "appliedId": "%s",\n  "entries": [{ "id": "%s", "name": "Kodeo" }]\n}\n' "$id" "$id" >"$lib/_meta.json.cli-tmp" ) \
    && mv "$lib/_meta.json.cli-tmp" "$lib/_meta.json"
}
cd_modo() { json_op "$(pasta_3p)/claude_desktop_config.json" merge "{\"deploymentMode\":\"3p\"}"; }
cd_devtools() { json_op "$(pasta_3p)/developer_settings.json" merge "{\"allowDevTools\":true}"; }
cd_reiniciar() {
  [ "${CLI_SEM_REINICIAR:-0}" = 1 ] && return 0
  pgrep -f '/Applications/Claude.app' >/dev/null 2>&1 || return 0
  osascript -e 'tell application "Claude" to quit' >/dev/null 2>&1; sleep 2
  pgrep -f '/Applications/Claude.app' >/dev/null 2>&1 && pkill -f '/Applications/Claude.app'; sleep 0.5
  open -a Claude 2>/dev/null || true
}
remover_claude_desktop() {
  local lib; lib="$(pasta_3p)/configLibrary"
  passo "Remover a configuração do Claude Desktop" bash -c '
    lib="$1"
    [ -f "$lib/_meta.json" ] || exit 0
    grep -q "\"name\": *\"Kodeo\"" "$lib/_meta.json" || exit 0
    id=$(grep -o "\"appliedId\": *\"[^\"]*\"" "$lib/_meta.json" | sed "s/.*: *\"//; s/\"$//")
    [ -n "$id" ] && rm -f "$lib/$id.json"
    rm -f "$lib/_meta.json"' _ "$lib"
  [ -f "$(pasta_3p)/claude_desktop_config.json" ] && passo "deploymentMode = 1p" json_op "$(pasta_3p)/claude_desktop_config.json" merge '{"deploymentMode":"1p"}'
  passo "Reiniciar o Claude (se estiver aberto)" cd_reiniciar
  true
}
aplicar_claude_desktop() {
  [ -n "$JSON_TOOL" ] || { printf '    %s✗%s Preciso do Node.js ou Python.\n' "$ERR" "$R"; FALHAS=$((FALHAS+1)); return; }
  passo "Configuração guiada (modelos + atalhos) em Claude-3p/configLibrary" cd_escrever
  passo "deploymentMode = 3p" cd_modo
  passo "Modo desenvolvedor (allowDevTools)" cd_devtools
  passo "Reiniciar o Claude (se estiver aberto)" cd_reiniciar
}

# ── OpenCode ───────────────────────────────────────────────────────────────
# Formato do V2 (v2.x): "providers" + "package" + "settings". O formato antigo
# ("provider" + "npm") é ignorado pelo V2 — o provedor simplesmente não aparece.
OC_CFG="$HOME/.config/opencode/opencode.json"; OC_KEY="$HOME/.config/opencode/kodeo-api-key"
oc_provider() {
  local modelos ant=""
  modelos=$(opencode_modelos_json)
  if [ -f "$OC_CFG" ]; then
    ant=$(json_ler "$OC_CFG" model)
    case "$ant" in kodeo/*) ant="";; esac
  fi
  opencode_aplicar "$BASE" "$CHAVE" "$modelos" "$OC_CFG" || return 1
  opencode_definir_modelo "$OC_CFG" "$PADRAO_ID" || return 1
  [ -n "$ant" ] && printf '%s' "$ant" >"$OC_CFG.modelo-anterior"
  return 0
}
oc_integracao() { # dá à chave um lugar na TUI (/connect)
  local j; j=$(opencode_integration_json); json_op "$OC_CFG" merge "$j"
}
oc_chave() {
  # A chave chega ao OpenCode por dois caminhos que não dependem de reiniciar nada:
  #  a) o bloco do shell (~/.zshrc) exporta KODEO_API_KEY, e o provedor declara
  #     env: ["KODEO_API_KEY"] — um serviço novo já nasce com ela;
  #  b) `opencode service set env` grava a chave no ambiente gerenciado do serviço.
  # O arquivo em ~/.config/opencode fica como referência para o desfazer e para
  # outras ferramentas. Nada disso escreve no SQLite do OpenCode.
  opencode_chave_arquivo "$CHAVE" "$OC_KEY"
  opencode_chave_servico "$CHAVE" >/dev/null 2>&1 || true
  return 0
}
aplicar_opencode() {
  [ -n "$JSON_TOOL" ] || { printf '    %s✗%s Preciso do Node.js ou Python.\n' "$ERR" "$R"; FALHAS=$((FALHAS+1)); return; }
  passo "Provedor e os modelos do plano em ~/.config/opencode/opencode.json" oc_provider
  passo "Integração para a chave aparecer em /connect" oc_integracao
  passo "Chave disponível para o OpenCode" oc_chave
  local f; for f in $(RC_FILES); do passo "KODEO_API_KEY em ${f/#$HOME/~} (o provedor lê do ambiente)" rc_escrever_bloco_codex "$f"; done
  passo "Modelo padrão: kodeo/$PADRAO_ID" true
}
remover_opencode() {
  local ant=""
  [ -f "$OC_CFG.modelo-anterior" ] && ant=$(cat "$OC_CFG.modelo-anterior" 2>/dev/null)
  passo "Tirar o provedor do opencode.json" remover_opencode_arq "$OC_CFG" "$ant"
  rm -f "$OC_KEY" "$OC_CFG.modelo-anterior"
  # se nenhuma outra ferramenta precisa da chave, tira do shell
  if ! grep -qs "api.kodeo.com.br" "$HOME/.claude/settings.json" 2>/dev/null &&
     ! grep -qs "model_providers.kodeo" "$CX_CFG" 2>/dev/null; then
    local f; for f in "$HOME/.zshrc" "$HOME/.bashrc"; do
      [ -f "$f" ] && grep -qs "^$MARCA_INI" "$f" && ! grep -qs "ANTHROPIC_BASE_URL" "$f" \
        && passo "Remover KODEO_API_KEY de ${f/#$HOME/~}" rc_remover_bloco "$f"
    done
  fi
  opencode_service_unset KODEO_API_KEY >/dev/null 2>&1 || true
  true
}
remover_opencode_arq() { # ARQUIVO MODELO_ANTERIOR
  local f="$1" ant="$2"
  [ -f "$f" ] || return 0
  local atual; atual=$(json_ler "$f" model)
  opencode_remover "$f" || return 1
  case "$atual" in
    kodeo/*)
      if [ -n "$ant" ]; then json_op "$f" merge "$(printf '{"model":"%s"}' "$ant")"
      else json_op "$f" del "model"; fi ;;
  esac
  return 0
}

# ── Codex / ChatGPT Desktop ────────────────────────────────────────────────
CX_CATALOGO="$CX_DIR/cli-setup-models.json"; CX_BK="$HOME/.config/cli-setup/codex-config.toml.anterior"
cx_baixar_catalogo() {
  mkdir -p "$CX_DIR" || return 1
  local tmp="$CX_CATALOGO.cli-tmp" raw="$CX_DIR/.codex-raw.cli-tmp"
  curl -s -m 30 -A "cli-setup/$VERSAO" "$BASE/v1/codex/modelos" -H "Authorization: Bearer $CHAVE" -o "$raw" 2>/dev/null
  grep -qs '"models"' "$raw" || { rm -f "$raw"; echo "não consegui baixar o catálogo do Codex"; return 1; }
  CATALOGO_CODEX=$(cat "$raw"); rm -f "$raw"
  export CATALOGO_CODEX CAT_PADRAO="$PADRAO_ID" JSON_TOOL
  catalogo_codex_json "$PADRAO_ID" >"$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$CX_CATALOGO" || return 1
  # confirma que o modelo padrão está no catálogo
  grep -qs "\"$PADRAO_ID\"" "$CX_CATALOGO" || { echo "o modelo $PADRAO_ID não está no catálogo do Codex"; return 1; }
  return 0
}
cx_sem_blocos() { awk '/^# >>> kodeo( provider)? >>>$/{d=1;next} /^# <<< kodeo( provider)? <<<$/{d=0;next} !d' "$1"; }
cx_escrever() {
  mkdir -p "$CX_DIR" || return 1
  [ -f "$CX_BK" ] || { mkdir -p "$(dirname "$CX_BK")"; [ -f "$CX_CFG" ] && cp "$CX_CFG" "$CX_BK"; }
  local corpo=""
  [ -f "$CX_CFG" ] && corpo=$(cx_sem_blocos "$CX_CFG")
  local cabeca cauda
  cabeca=$(printf '%s\n' "$corpo" | awk '/^\[/{exit} {print}' | grep -vE '^\s*(model|model_provider|model_catalog_json)\s*=')
  cauda=$(printf '%s\n' "$corpo" | awk 'f{print} /^\[/{if(!f){f=1;print}}')
  {
    cx_bloco_topo "$PADRAO_ID" "$CX_CATALOGO"
    [ -n "$cabeca" ] && printf '%s\n' "$cabeca"
    [ -n "$cauda" ] && printf '%s\n' "$cauda"
    printf '\n'
    cx_bloco_provider "$BASE"
  } >"$CX_CFG.cli-tmp" && mv "$CX_CFG.cli-tmp" "$CX_CFG"
}
cx_remover() {
  rm -f "$CX_CATALOGO"
  [ -f "$CX_CFG" ] || return 0
  if [ -f "$CX_BK" ]; then mv "$CX_BK" "$CX_CFG"; return 0; fi
  grep -qs "^# >>> kodeo" "$CX_CFG" || return 0
  local resto; resto=$(cx_sem_blocos "$CX_CFG")
  if [ -z "$(printf '%s' "$resto" | tr -d '[:space:]')" ]; then rm -f "$CX_CFG"; else printf '%s\n' "$resto" >"$CX_CFG"; fi
}
cx_app() {
  [ "$(uname -s)" = Darwin ] || return 0
  local a; for a in "/Applications/ChatGPT.app" "/Applications/Codex.app" "$HOME/Applications/ChatGPT.app" "$HOME/Applications/Codex.app"; do
    [ -d "$a" ] && { printf '%s' "$a"; return 0; }
  done
}
cx_app_reiniciar() {
  [ "${CLI_SEM_REINICIAR:-0}" = 1 ] && return 0
  local a; a=$(cx_app); [ -n "$a" ] || return 0
  pgrep -f "$a/Contents/MacOS/" >/dev/null 2>&1 || return 0
  osascript -e 'tell application "ChatGPT" to quit' >/dev/null 2>&1; sleep 2
  pkill -f "$a/Contents/MacOS/" 2>/dev/null; sleep 0.5
  open "$a" 2>/dev/null || true
}
aplicar_codex() {
  passo "Lista de modelos do plano em ~/.codex/cli-setup-models.json" cx_baixar_catalogo
  passo "Provedor e modelo padrão ($PADRAO_ID) em ~/.codex/config.toml" cx_escrever
  local f; for f in $(RC_FILES); do passo "KODEO_API_KEY em ${f/#$HOME/~}" rc_escrever_bloco_codex "$f"; done
  passo "Teste de conexão (responses)" teste_responses
  [ -n "$(cx_app)" ] && passo "Reiniciar o ChatGPT Desktop (se estiver aberto)" cx_app_reiniciar
  true
}
remover_codex() {
  passo "Devolver o ~/.codex/config.toml como estava" cx_remover
  local f; for f in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [ -f "$f" ] && grep -qs "^$MARCA_INI" "$f" && ! grep -qs "ANTHROPIC_BASE_URL" "$f" && passo "Remover KODEO_API_KEY de ${f/#$HOME/~}" rc_remover_bloco "$f"
  done
  [ -n "$(cx_app)" ] && passo "Reiniciar o ChatGPT Desktop (se estiver aberto)" cx_app_reiniciar
  true
}

# ── resumo ─────────────────────────────────────────────────────────────────
FEITAS=(); REMOVIDAS=()
tela_aplicar() {
  tela "5/$TOTAL  Aplicar" 5
  rodape "aguarde:aplicando"
  local i
  for ((i=0;i<${#NOMES[@]};i++)); do
    [ "${SEL[$i]}" -eq 1 ] || continue
    if [ "${CONF[$i]}" -eq 1 ]; then
      printf '%s  %s%s%s %sdesconfigurar%s\n' "$ESPACO" "$B$W" "${NOMES[$i]}" "$R" "$G" "$R"
      case "${IDS[$i]}" in claude-code) remover_claude_code;; claude-app) remover_claude_desktop;; opencode) remover_opencode;; codex) remover_codex;; esac
      REMOVIDAS+=("${NOMES[$i]}")
    else
      printf '%s  %s%s%s %sconfigurar%s\n' "$ESPACO" "$B$W" "${NOMES[$i]}" "$R" "$G" "$R"
      case "${IDS[$i]}" in claude-code) aplicar_claude_code;; claude-app) aplicar_claude_desktop;; opencode) aplicar_opencode;; codex) aplicar_codex;; esac
      FEITAS+=("${NOMES[$i]}")
    fi
    printf '\n'
  done
  tela_resumo
}

tela_resumo() {
  tela "4/$TOTAL  Pronto" 4
  local m="${CHAVE:0:9}…${CHAVE: -4}" l="" l2="" x
  for x in "${FEITAS[@]+"${FEITAS[@]}"}"; do l="$l${l:+, }$x"; done
  for x in "${REMOVIDAS[@]+"${REMOVIDAS[@]}"}"; do l2="$l2${l2:+, }$x"; done
  caixa_topo "Pronto"
  caixa_linha "" 0
  caixa_linha "${G}Chave          $R$m" $((15+${#m}))
  caixa_linha "${G}Modelos        $R$CAT_PLANO_N do plano  ·  padrão ${W}$PADRAO_ID$R" $((15+${#PADRAO_ID}+20))
  [ -n "$l" ]  && caixa_linha "${G}Configuradas   $R$l" $((15+${#l}))
  [ -n "$l2" ] && caixa_linha "${G}Desconfiguradas $R$l2" $((16+${#l2}))
  caixa_linha "" 0
  if [ "$FALHAS" -gt 0 ]; then caixa_linha "${ERR}${FALHAS} passo(s) falharam$R — veja acima." $(( ${#FALHAS}+40 ))
  elif [ -n "$l" ]; then caixa_linha "Abra um terminal novo e use as ferramentas." 42
  else caixa_linha "Tudo removido." 14; fi
  caixa_fundo
  if [ -n "$l" ] && [ $((LINHAS)) -ge 20 ]; then
    printf '%s\n%s  %sAbra um terminal novo para o shell ler o bloco novo.%s\n' "$ESPACO" "$ESPACO" "$G" "$R"
  fi
  rodape "enter:sair"
  local k; while :; do k=$(tecla); case "$k" in enter|q|Q|eof) break;; esac; done
  printf '%s[%d;1H\n' "$E" "$LINHAS"
}

# ══ principal ═════════════════════════════════════════════════════════════
exige_terminal
abertura
stty -echo 2>/dev/null <"$TTY" || true
detectar
if chave_ok "$CHAVE"; then CHAVE_DO_COMANDO=1; tela_chave_do_comando; fi
while :; do
  [ "$CHAVE_DO_COMANDO" -eq 0 ] && tela_chave
  tela_ferramentas || continue
  tela_modelos && break
done
tela_aplicar
