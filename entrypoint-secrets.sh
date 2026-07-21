#!/bin/bash
# Lê variáveis "<VAR>_FILE" (padrão Docker secrets) e as expõe como "<VAR>"
# antes de iniciar o Keycloak. O Keycloak não suporta esse padrão nativamente
# (https://github.com/keycloak/keycloak/discussions/10938), então resolvemos
# aqui no entrypoint em vez de colocar senhas em texto plano no compose.
set -euo pipefail

file_env() {
  local var="$1"
  local file_var="${var}_FILE"
  local file_path="${!file_var:-}"

  if [[ -n "$file_path" ]]; then
    if [[ ! -f "$file_path" ]]; then
      echo "entrypoint-secrets: arquivo '$file_path' referenciado por $file_var não encontrado" >&2
      exit 1
    fi
    export "$var"="$(cat "$file_path")"
    unset "$file_var"
  fi
}

file_env KC_DB_PASSWORD
file_env KC_BOOTSTRAP_ADMIN_PASSWORD

exec /opt/keycloak/bin/kc.sh "$@"
