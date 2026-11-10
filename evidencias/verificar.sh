#!/usr/bin/env bash
# evidencias/verificar.sh — reproduz a coleta de evidência do roteamento.
#
# Uso:
#   KODEO_KEY="ck_..." bash evidencias/verificar.sh
#   KODEO_KEY="ck_..." bash evidencias/verificar.sh > relatorio.txt
#
# O que faz: pede cada modelo do plano com a MESMA pergunta, e registra
#   - o que o cliente pediu
#   - o que o campo "model" da resposta diz
#   - o que o texto respondeu
#   - o id da resposta e os tokens (para comparar se é o mesmo backend)
#   - os headers x-kodeo-provedor / x-kodeo-roteamento / x-kodeo-substituto
#
# A prova está na combinação: se quatro modelos distintos devolvem o mesmo id,
# o mesmo texto (mesmo SHA1) e os mesmos tokens, é o mesmo backend respondendo.
set -u

K="${KODEO_KEY:-${CLI_KEY:-}}"
BASE="${CLI_BASE:-https://api.kodeo.com.br}"
if [ -z "$K" ]; then
  printf 'falta a chave: KODEO_KEY="ck_..." bash %s\n' "$0" >&2
  exit 2
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/kodeo-ev.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

sha1() { printf '%s' "$1" | shasum -a 1 2>/dev/null | cut -c1-16 || printf '%s' "$1" | sha1sum | cut -c1-16; }

# campos de um JSON, sem depender de node/python
campo() { # ARQUIVO CAMINHO_PYTHON
  python3 -c "
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: print('(invalido)'); raise SystemExit
if d.get('error'): print('ERRO'); raise SystemExit
v=d
for p in sys.argv[2].split('.'):
    if isinstance(v,dict): v=v.get(p)
    else: v=None; break
print(v if v is not None else '')" "$1" "$2" 2>/dev/null
}

echo "coleta: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "gateway: $BASE"
echo

# ── plano ──────────────────────────────────────────────────────────────────
echo "── modelos do plano (/v1/me) ──────────────────────────────────────────"
curl -s -m 20 "$BASE/v1/me" -H "x-api-key: $K" -o "$TMP/me.json" 2>/dev/null
python3 -c "
import json
try: d=json.load(open('$TMP/me.json'))
except Exception: d={}
print('plano:', d.get('plano',{}).get('nome','?'))
ms=d.get('modelos') or []
print('modelos:', len(ms))
for m in ms: print('  ', m)" 2>/dev/null
echo

MODELOS=$(python3 -c "
import json
try: d=json.load(open('$TMP/me.json'))
except Exception: d={}
print('\n'.join(d.get('modelos') or []))" 2>/dev/null)
[ -z "$MODELOS" ] && { echo "não consegui ler o plano"; exit 1; }

PERGUNTA='Qual e o seu modelo? Responda apenas o nome.'

# ── chat/completions ───────────────────────────────────────────────────────
echo "── POST /v1/chat/completions ──────────────────────────────────────────"
printf '%-20s %-18s %-30s %-34s %-8s %s\n' "PEDIDO" "corpo.model" "resposta" "id" "tokens" "x-kodeo-substituto"
printf '%s\n' "────────────────────────────────────────────────────────────────────────────────────────────────────────────────"
for m in $MODELOS; do
  curl -s -D "$TMP/h.txt" -o "$TMP/b.json" -m 60 "$BASE/v1/chat/completions" \
    -H "Authorization: Bearer $K" -H 'content-type: application/json' \
    -d "{\"model\":\"$m\",\"messages\":[{\"role\":\"user\",\"content\":\"$PERGUNTA\"}],\"max_tokens\":40}" 2>/dev/null

  sub=$(grep -i 'x-kodeo-substituto' "$TMP/h.txt" | tr -d '\r' | sed 's/.*: //')
  corpo=$(campo "$TMP/b.json" "model")
  txt=$(python3 -c "
import json
try:
    d=json.load(open('$TMP/b.json'))
    print((d['choices'][0]['message']['content'] or '').strip().replace(chr(10),' ')[:28])
except Exception: print('(vazio)')" 2>/dev/null)
  rid=$(campo "$TMP/b.json" "id")
  tok=$(campo "$TMP/b.json" "usage.total_tokens")

  printf '%-20s %-18s %-30s %-34s %-8s %s\n' "$m" "$corpo" "$txt" "$rid" "$tok" "${sub:--}"
  sleep 1
done
echo

# ── prova do mesmo backend ─────────────────────────────────────────────────
echo "── o mesmo id apareceu em mais de um modelo? ──────────────────────────"
for m in $MODELOS; do
  curl -s -o "$TMP/b2_$m.json" -D "$TMP/h2.txt" -m 60 "$BASE/v1/chat/completions" \
    -H "Authorization: Bearer $K" -H 'content-type: application/json' \
    -d "{\"model\":\"$m\",\"messages\":[{\"role\":\"user\",\"content\":\"$PERGUNTA\"}],\"max_tokens\":40}" 2>/dev/null
  python3 -c "
import json,hashlib
m='$m'
try: d=json.load(open('$TMP/b2_%s.json'%m))
except Exception: raise SystemExit
if d.get('error'): raise SystemExit
t=(d['choices'][0]['message']['content'] or '').strip()
print('%s\t%s\t%s\t%s' % (m, d.get('id'), hashlib.sha1(t.encode()).hexdigest()[:16], (d.get('usage') or {}).get('total_tokens')))" 2>/dev/null
  sleep 1
done | sort -k2 | awk -F'\t' '
{ if ($2 != prev) { if (prev != "") printf "\n"; printf "  id=%s  tokens=%s\n", $2, $4; prev=$2 }
  printf "     %-20s sha1(texto)=%s\n", $1, $3 }'
echo

# ── responses ──────────────────────────────────────────────────────────────
echo "── POST /v1/responses (o endpoint do Codex) ──────────────────────────"
printf '%-20s %-18s %-30s %s\n' "PEDIDO" "campo.model" "texto real" "x-kodeo-substituto"
printf '%s\n' "─────────────────────────────────────────────────────────────────────────────────────────"
for m in $MODELOS; do
  curl -s -D "$TMP/hr.txt" -o "$TMP/br.json" -m 60 "$BASE/v1/responses" \
    -H "Authorization: Bearer $K" -H 'content-type: application/json' \
    -d "{\"model\":\"$m\",\"input\":\"$PERGUNTA\",\"max_output_tokens\":40,\"store\":false}" 2>/dev/null
  sub=$(grep -i 'x-kodeo-substituto' "$TMP/hr.txt" | tr -d '\r' | sed 's/.*: //')
  corpo=$(campo "$TMP/br.json" "model")
  txt=$(python3 -c "
import json
try:
    d=json.load(open('$TMP/br.json'))
    if d.get('error'): print('ERRO'); raise SystemExit
    t=''.join(c.get('text','') for o in d.get('output',[]) for c in o.get('content',[]))
    print(t.strip().replace(chr(10),' ')[:28])
except Exception: print('(vazio)')" 2>/dev/null)
  printf '%-20s %-18s %-30s %s\n' "$m" "$corpo" "$txt" "${sub:--}"
  sleep 1
done
echo

echo "── leitura ────────────────────────────────────────────────────────────"
cat <<'TXT'
  - Se "corpo.model" for diferente do PEDIDO, o gateway serviu outro modelo
    e declarou isso no campo model.
  - Se x-kodeo-substituto aparecer, o próprio gateway informa a troca.
  - Se dois modelos retornarem o MESMO id e o MESMO sha1 do texto, é o mesmo
    backend respondendo aos dois.
  - Em /v1/responses o campo model ecoa o pedido (não o servido): a troca só
    aparece no header e no texto.
TXT