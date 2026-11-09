#!/usr/bin/env bash
# lib/opencode.sh — configura o OpenCode no formato do V2 (v2.x).
#
# O script antigo gravava "provider" + "npm", que é o formato do V1. No V2 o campo
# é "providers", o runtime é escolhido por "package" e o endpoint vai em "settings".
# Gravar o formato antigo deixa o provedor invisível: o OpenCode ignora e o usuário
# fica sem os modelos.
#
# A chave é o único ponto que não dá para escrever em arquivo: o V2 guarda credencial
# no SQLite do servidor, e a documentação proíbe editar esse banco à mão. Então o
# configurador declara o provedor e a integração, e oferece a chave por três caminhos,
# na ordem do menos para o mais intrusivo:
#   1. opencode auth login <id> --method key   (a TUI pede e o OpenCode guarda)
#   2. variável de ambiente no serviço          (opencode service set env)
#   3. {file:...} apontando para um arquivo      (último recurso, se o runtime aceitar)

# opencode_versao → "1" ou "2" (vazio se não instalado)
opencode_versao() {
  command -v opencode >/dev/null 2>&1 || return 1
  local v; v=$(opencode --version 2>/dev/null | head -1)
  case "$v" in
    *2.*) printf '2' ;;
    *1.*) printf '1' ;;
    *)    printf '2' ;;   # desconhecida: assume o formato atual
  esac
}

# opencode_provider_json MODELOS_JSON → o objeto do provedor em V2
# MODELOS_JSON vem de opencode_modelos_json (lib/geradores.sh), no formato que o V2 lê.
opencode_provider_json() { # BASE MODELOS_JSON
  local base="$1" modelos="$2"
  printf '{"providers":{"kodeo":{"name":"Kodeo","env":["KODEO_API_KEY"],"package":"@opencode/ai/providers/openai-compatible","settings":{"baseURL":"%s/v1"},"models":%s}}}' \
    "$base" "$modelos"
}

# opencode_integration_json → a integração que dá à chave um lugar na TUI (/connect)
# Sem isso o provedor aparece, mas não há onde colar a chave.
opencode_integration_json() {
  printf '{"integrations":{"kodeo":{"name":"Kodeo","methods":[{"type":"key","label":"Kodeo API key"}]}}}'
}

# opencode_aplicar BASE CHAVE MODELOS_JSON ARQUIVO
# Devolve 0 se o provider ficou gravado; a chave é tratada pelo chamador.
opencode_aplicar() {
  local base="$1" modelos="$3" cfg="$4"
  local prov; prov=$(opencode_provider_json "$base" "$modelos")
  json_op "$cfg" merge "$prov"
}

# opencode_definir_modelo ARQUIVO MODELO
opencode_definir_modelo() {
  json_op "$1" merge "{\"model\":\"kodeo/$2\"}"
}

# opencode_chave_cli ID CHAVE → tenta o caminho oficial e não interativo
# Em muitas versões o método "key" exige terminal; a função devolve 1 nesse caso
# e o chamador cai para a variável de ambiente do serviço.
opencode_chave_cli() {
  command -v opencode >/dev/null 2>&1 || return 1
  opencode auth login "$1" --method key --answer "apiKey=$2" >/dev/null 2>&1
}

# opencode_chave_servico CHAVE → grava a chave no ambiente do servidor em segundo plano
# Isso a torna disponível para o runtime sem tocar no banco.
opencode_chave_servico() {
  command -v opencode >/dev/null 2>&1 || return 1
  opencode service set env KODEO_API_KEY "$1" >/dev/null 2>&1
}

# opencode_chave_arquivo CHAVE CAMINHO → deixa a chave num arquivo (600) para {file:}
opencode_chave_arquivo() {
  local chave="$1" arq="$2"
  mkdir -p "$(dirname "$arq")" || return 1
  ( umask 077; printf '%s' "$chave" >"$arq" )
}

# opencode_remover ARQUIVO → tira o provedor e devolve o modelo anterior
opencode_remover() {
  local cfg="$1"
  [ -f "$cfg" ] || return 0
  json_op "$cfg" del "providers" 2>/dev/null
  # se o arquivo ficou só com chaves vazias, remove
  local t; t=$(tr -d '[:space:]{}' <"$cfg" 2>/dev/null)
  [ -z "$t" ] && rm -f "$cfg"
  return 0
}
# opencode_service_unset VAR → tira a variável do ambiente do serviço
opencode_service_unset() {
  command -v opencode >/dev/null 2>&1 || return 1
  opencode service unset env "$1" >/dev/null 2>&1
}
