#!/usr/bin/env bash
# lib/json.sh — leitura e escrita de JSON independentes do leitor disponível.
# A ideia: uma função por operação, e o node/python escolhido uma vez em JSON_TOOL.
# Nenhuma função aqui adivinha o formato: o arquivo é lido inteiro, validado, e
# gravado de forma atômica (tmp + rename). Arquivo corrompido nunca é sobrescrito.

# json_vazio ARQUIVO → 0 se o arquivo não existe, está vazio ou só tem espaços
json_vazio() { [ ! -f "$1" ] || [ -z "$(tr -d '[:space:]' <"$1" 2>/dev/null)" ]; }

# json_valido ARQUIVO → 0 se é um objeto JSON válido
json_valido() {
  [ -f "$1" ] || return 0
  if [ "${JSON_TOOL}" = node ]; then
    node -e 'const fs=require("fs");try{const j=JSON.parse(fs.readFileSync(process.argv[1],"utf8")||"{}");if(!j||typeof j!=="object"||Array.isArray(j))process.exit(1)}catch{process.exit(1)}' "$1" 2>/dev/null
  else
    python3 -c 'import json,sys
try:
  j=json.load(open(sys.argv[1],encoding="utf-8"))
  raise SystemExit(0 if isinstance(j,dict) else 1)
except SystemExit: raise
except Exception: raise SystemExit(1)' "$1" 2>/dev/null
  fi
}

# json_ler ARQUIVO CAMPO → imprime o valor (string crua; objeto/array em JSON)
json_ler() {
  local arq="$1" campo="$2"
  [ -f "$arq" ] || return 0
  if [ "${JSON_TOOL}" = node ]; then
    node -e '
const fs=require("fs");const f=process.argv[1],c=process.argv[2];
let j={};try{j=JSON.parse(fs.readFileSync(f,"utf8")||"{}")}catch{process.exit(0)}
let v=j;
for(const p of c.split(".")){ if(v===null||typeof v!=="object"){v=undefined;break} v=v[p]; }
if(v===undefined||v===null)process.exit(0);
process.stdout.write(typeof v==="string"?v:JSON.stringify(v));' "$arq" "$campo" 2>/dev/null
  else
    python3 -c '
import json,sys
f,c=sys.argv[1],sys.argv[2]
try: j=json.load(open(f,encoding="utf-8"))
except Exception: raise SystemExit(0)
v=j
for p in c.split("."):
    if not isinstance(v,dict): v=None; break
    v=v.get(p)
if v is None: raise SystemExit(0)
sys.stdout.write(v if isinstance(v,str) else json.dumps(v))' "$arq" "$campo" 2>/dev/null
  fi
}

# json_op ARQUIVO OPERACAO [JSON]
#   merge        mescla JSON no objeto (objetos internos são fundidos, não trocados)
#   merge-keep   só adiciona chaves que ainda não existem
#   del          remove as chaves listadas (separadas por vírgula)
json_op() {
  local arq="$1" op="$2" extra="${3:-}" dir; dir=$(dirname "$arq"); mkdir -p "$dir" || return 1
  if [ "${JSON_TOOL}" = node ]; then
    CLI_ARQ="$arq" CLI_OP="$op" CLI_EXTRA="$extra" node -e '
const fs=require("fs"),f=process.env.CLI_ARQ,op=process.env.CLI_OP,extra=process.env.CLI_EXTRA||"";
let t="";try{t=fs.readFileSync(f,"utf8")}catch{}
let j={};
if(t.trim()){try{j=JSON.parse(t)}catch{console.error("arquivo corrompido, nada foi alterado");process.exit(2)}}
if(!j||typeof j!=="object"||Array.isArray(j)){console.error("não é um objeto JSON");process.exit(2)}
if(op==="merge"){
  const add=JSON.parse(extra);
  for(const k of Object.keys(add)){
    const v=add[k];
    if(v&&typeof v==="object"&&!Array.isArray(v)&&j[k]&&typeof j[k]==="object"&&!Array.isArray(j[k]))
      j[k]=Object.assign({},j[k],v);
    else j[k]=v;
  }
}else if(op==="merge-keep"){
  const add=JSON.parse(extra);
  for(const k of Object.keys(add)) if(j[k]===undefined) j[k]=add[k];
}else if(op==="del"){
  for(const k of extra.split(",")) if(k) delete j[k];
}else{console.error("operação desconhecida");process.exit(3)}
const tmp=f+".cli-tmp";
fs.writeFileSync(tmp,JSON.stringify(j,null,2)+"\n");
fs.renameSync(tmp,f);'
  else
    CLI_ARQ="$arq" CLI_OP="$op" CLI_EXTRA="$extra" python3 -c '
import json,os,sys
f=os.environ["CLI_ARQ"];op=os.environ["CLI_OP"];extra=os.environ.get("CLI_EXTRA","")
try: t=open(f,encoding="utf-8").read()
except FileNotFoundError: t=""
j={}
if t.strip():
    try: j=json.loads(t)
    except Exception:
        print("arquivo corrompido, nada foi alterado"); raise SystemExit(2)
if not isinstance(j,dict): raise SystemExit(2)
if op=="merge":
    for k,v in json.loads(extra).items():
        if isinstance(v,dict) and isinstance(j.get(k),dict): j[k]={**j[k],**v}
        else: j[k]=v
elif op=="merge-keep":
    for k,v in json.loads(extra).items():
        if k not in j: j[k]=v
elif op=="del":
    for k in extra.split(","):
        if k: j.pop(k,None)
else: raise SystemExit(3)
tmp=f+".cli-tmp"
open(tmp,"w",encoding="utf-8").write(json.dumps(j,indent=2,ensure_ascii=False)+"\n")
os.replace(tmp,f)'
  fi
}