#!/usr/bin/env bash
# Verifica que todas as partes da interface têm a largura que dizem ter.
# Carrega as funções do instalar.sh sem executar o corpo.
set -u
REPO="/Users/samuelbacaro/Documents/OpenCode/CLI Setup/meu-configurador"
cd "$REPO" || exit 1

E=$'\033'
R="$E[0m"; B="$E[1m"; W="$E[97m"; G="$E[38;2;122;126;136m"; OK="$E[32m"; ERR="$E[31m"
ACC_F="$E[38;2;126;206;255m"
LINHAS=30; COLS=120; LARG=76; ETAPAS_LARG=16
if [ "$COLS" -ge $((LARG+ETAPAS_LARG+4)) ]; then MARGEM=$(( (COLS-(LARG+ETAPAS_LARG))/2 ))
else MARGEM=$(( (COLS-LARG)/2 )); fi
ESPACO=$(printf '%*s' "$MARGEM" '')
tracos() { local i s=""; for ((i=0;i<$1;i++)); do s="${s}─"; done; printf '%s' "$s"; }
regua() { tracos $((LARG-4)); }

# extrai só as definições de desenho
sed -n '/^# As três partes da caixa/,/^SPIN=/p' instalar.sh | sed '$d' > /tmp/caixas.sh
. /tmp/caixas.sh

larg() { python3 -c '
import re,sys
raw=sys.stdin.read().rstrip("\n")
print(len(re.sub(r"\x1b\[[0-9;]*m","",raw)))'; }

falhas=0
checa() { # nome, esperado, obtido
  if [ "$2" = "$3" ]; then printf '  ok    %-28s %s\n' "$1" "$3"
  else printf '  FALHA %-28s esperado %s, obtido %s\n' "$1" "$2" "$3"; falhas=$((falhas+1)); fi
}

T=$(caixa_topo "Pronto" | larg);              checa "caixa_topo" "$((LARG+MARGEM))" "$T"
L=$(caixa_linha "" 0 | larg);                 checa "caixa_linha vazia" "$((LARG+MARGEM))" "$L"
TXT="Chave   ck_bd0c7a…b916"
L2=$(caixa_linha "${G}${TXT}${R}" "${#TXT}" | larg); checa "caixa_linha com texto" "$((LARG+MARGEM))" "$L2"
F=$(caixa_fundo | larg);                      checa "caixa_fundo" "$((LARG+MARGEM))" "$F"

# a regra do cabeçalho e do rodapé
G1=$(printf '%s  %s%s%s' "$ESPACO" "$G" "$(regua)" "$R" | larg); checa "regua" "$((LARG-4+MARGEM+2))" "$G1"

echo
echo "falhas: $falhas"
[ "$falhas" = 0 ] && printf '\033[32mCAIXAS OK\033[0m\n'