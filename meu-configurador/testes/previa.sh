#!/usr/bin/env bash
# Renderiza as telas do configurador num tamanho fixo, sem TUI, para conferir o layout.
# Uso: bash testes/previa.sh [linhas] [colunas]
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO" || exit 1

export CLI_LINHAS="${1:-30}" CLI_COLS="${2:-120}"
# carrega tudo menos o corpo principal (que abre a TUI)
awk '/^# ══ principal/{exit} {print}' instalar.sh > /tmp/previa-corpo.sh
export BASE="https://api.kodeo.com.br" JSON_TOOL=node TTY=/dev/null
export CHAVE="ck_bd0c7af04cc4a69fd3e00d46a1f3d9b4f3bc24d28b916616"
. /tmp/previa-corpo.sh

# estado simulado
NOMES=("Claude Code" "Claude Desktop" "OpenCode" "Codex + ChatGPT")
CONF=(1 0 0 0); SEL=(0 1 1 1); INST=(1 0 1 1)
CAT_N=22; PADRAO_ID="claude-opus-5.5"; OPUS_ID="claude-opus-5.5"
HAIKU_ID="claude-haiku-5.5"; SONNET_ID=""

larg() { python3 -c 'import re,sys;print(len(re.sub(r"\x1b\[[0-9;]*m","",sys.stdin.read().rstrip("\n"))))'; }

echo "tamanho: ${COLS}x${LINHAS}  |  bloco: ${LARG}  |  margem: ${MARGEM}"
echo "──────────────── tela 2 (ferramentas) ────────────────"
tela "2/$TOTAL  Ferramentas" 2
linha "${B}${W}Passo 2 de 4 — o que configurar.${R}"
linha ""
linha "O que já está configurado pode ser desconfigurado."
linha "${G}Codex e ChatGPT Desktop usam o mesmo arquivo: marcar um configura os dois.${R}"
linha ""
n=${#NOMES[@]}; ln=0
for ((i=0;i<n;i++)); do [ ${#NOMES[$i]} -gt $ln ] && ln=${#NOMES[$i]}; done
ln=$((ln+2))
for ((i=0;i<n;i++)); do
  pre="  "; caixa="${G}[ ]${R}"; estado="${G}não configurado${R}"; esc=15; acao="configurar"
  [ "$i" -eq 1 ] && pre="${ACC_F}❯${R} "
  [ "${SEL[$i]}" -eq 1 ] && caixa="${ACC_F}[x]${R}"
  if [ "${CONF[$i]}" -eq 1 ]; then estado="${OK}configurado${R}"; esc=11; acao="desconfigurar"; fi
  [ "${INST[$i]}" -eq 0 ] && [ "${CONF[$i]}" -eq 0 ] && { estado="${G}não encontrado${R}"; esc=14; }
  if [ "${SEL[$i]}" -eq 1 ]; then acao="${W}→ ${acao}${R}"; else acao="${G}  ${acao}${R}"; fi
  printf '%s  %s%s %s%s%*s%s%*s%s\n' "$ESPACO" "$pre" "$caixa" "$W" "${NOMES[$i]}" $((ln-${#NOMES[$i]})) '' "$estado" $((23-esc)) '' "$acao"
done
printf '%s\n' "$(printf '%s  %s' "$ESPACO" "$(dicas '↑↓:mover' 'espaço:marcar' 'enter:continuar' 'ctrl+c:sair')")"
echo
echo "──────────────── tela 4 (resumo) ────────────────"
tela "4/$TOTAL  Pronto" 4
caixa_topo "Pronto"
caixa_linha "" 0
c1="${G}Chave          ${R}ck_bd0c7a…b916"
c2="${G}Modelos        ${R}22 do plano  ·  padrão claude-opus-5.5"
c3="${G}Configuradas   ${R}Claude Desktop, OpenCode, Codex + ChatGPT"
c4="Abra um terminal novo e use as ferramentas."
vis() { python3 -c 'import re,sys;print(len(re.sub(r"\x1b\[[0-9;]*m","",sys.argv[1])))' "$1"; }
caixa_linha "$c1" "$(vis "$c1")"
caixa_linha "$c2" "$(vis "$c2")"
caixa_linha "$c3" "$(vis "$c3")"
caixa_linha "" 0
caixa_linha "$c4" "$(vis "$c4")"
caixa_fundo
echo
echo "──────────────── medidas ────────────────"
printf '  topo  %s\n' "$(caixa_topo "Pronto" | larg)"
printf '  linha %s\n' "$(caixa_linha "$c1" "$(vis "$c1")" | larg)"
printf '  fundo %s\n' "$(caixa_fundo | larg)"
printf '  alvo  %s (LARG+MARGEM)\n' "$((LARG+MARGEM))"