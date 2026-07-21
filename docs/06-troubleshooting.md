# Troubleshooting

## Inicialização da stack

### `postgres` fica `unhealthy` ou reiniciando

- Verifique `docker compose logs postgres`
- Confirme que `secrets/postgres_password.txt` existe e não está vazio
- Se o volume `postgres_data` já existia de uma tentativa anterior com outra
  senha, o Postgres **não** vai aceitar a nova senha do secret automaticamente
  (a senha só é aplicada na criação inicial do volume). Nesse caso, ou você
  faz `ALTER USER` manualmente (ver [05-operacao.md](05-operacao.md#senha-do-postgres))
  ou remove o volume (⚠️ **apaga todos os dados**) e sobe do zero

### Keycloak: `Failed to obtain JDBC connection`

- Confirme que o Postgres está `healthy` (`docker compose ps`)
- Confirme que `secrets/postgres_password.txt` tem exatamente a mesma senha
  que está de fato configurada no Postgres (ver item acima se o volume já
  existia de antes com outra senha)

### Keycloak reinicia em loop / `healthcheck` nunca fica `healthy`

- Rode `docker compose logs keycloak` e procure a exceção real — o
  healthcheck só reflete se o processo respondeu, a causa raiz sempre aparece
  no log
- Confirme que `KC_HOSTNAME` está definido no `.env` (é obrigatório —
  o compose falha explicitamente se estiver vazio, mas confira mesmo assim)

### Proxy externo retorna `502 Bad Gateway` / `Bad Gateway`

- Normal nos primeiros ~30-60 segundos enquanto o Keycloak ainda sobe —
  configure o proxy externo (Coolify ou outro) para só rotear depois do
  healthcheck do Keycloak passar, se ele suportar isso
- Se persistir: `docker compose logs keycloak` para confirmar que ele
  realmente terminou de subir e está `healthy` (`docker compose ps`)
- Confirme que o proxy está apontando para `keycloak:8080` (HTTP, não HTTPS)
  na mesma rede Docker

## Certificados

### `entrypoint-secrets: arquivo '...' referenciado por ..._FILE não encontrado`

- O `docker-compose.yml` está apontando para `/run/secrets/...`, que só
  existe se o `secrets:` do serviço estiver corretamente declarado e o
  arquivo referenciado em `secrets:` (nível raiz do compose) existir de fato
  em `./secrets/`. Rode `scripts/generate-secrets.ps1` se ainda não gerou

### Navegador mostra aviso de certificado inválido

- O certificado TLS público é responsabilidade do proxy externo (fora deste
  compose) — verifique lá o certificado configurado (Coolify: aba de
  domínio/SSL do recurso). Ver [04-certificados-tls.md](04-certificados-tls.md)

### Erro de redirecionamento infinito / "We're sorry..." no login

Geralmente é `KC_HOSTNAME` não batendo com a URL real que o navegador usa,
ou o Keycloak não confiando nos cabeçalhos do proxy:

- Confirme que `KC_HOSTNAME` no `.env` é exatamente a URL pública
  (`https://auth.suaempresa.com`, sem barra no final)
- Confirme que `PROXY_TRUSTED_ADDRESSES` cobre o IP interno de onde o proxy
  externo fala com o Keycloak (o range default `172.16.0.0/12` cobre as redes
  Docker padrão — se você customizou as sub-redes do compose, ou a Coolify usa
  uma rede fora desse range, ajuste aqui)

## Federação LDAP

### `Test connection` falha: `PKIX path building failed` / `unable to find valid certification path`

O Keycloak não confia no certificado apresentado pelo Domain Controller na
porta 636:

- Confirme que o certificado da CA está em `certs/` (qualquer nome `.pem`/`.crt`)
- Confirme que `KC_TRUSTSTORE_PATHS=/opt/keycloak/certs` está definido
  (já vem assim no `docker-compose.yml` deste projeto)
- **Reinicie o Keycloak** depois de adicionar/trocar o certificado — o
  truststore é carregado no boot, não recarrega sozinho:
  ```powershell
  docker compose restart keycloak
  ```

### `Test connection` falha: erro de hostname / certificate does not match

- A Connection URL precisa usar o **hostname** do DC (`AD_DC_HOSTNAME`), não
  o IP — o Keycloak faz *strict hostname checking* contra o CN/SAN do
  certificado. Ver [03-federacao-ad.md](03-federacao-ad.md#7-validação-de-hostname-no-ldaps)
- Confirme que `extra_hosts` no `docker-compose.yml` resolve esse hostname
  para o IP certo dentro do container:
  ```powershell
  docker compose exec keycloak getent hosts dc01.meudominio.local
  ```

### `Test authentication` falha, mas `Test connection` funciona

- Confirme Bind DN e Bind Credential (senha da conta de serviço) —
  copiar/colar errado é a causa mais comum
- Confirme que a conta de serviço não está bloqueada/expirada no AD
- Confirme que o **Users DN** realmente contém o usuário de teste usado

### Conexão cai depois de um tempo / timeouts intermitentes

- Verifique políticas de timeout de conexão do próprio AD/firewall entre o
  host Docker e o DC
- Se o ambiente tiver múltiplos DCs e um deles cair, a federação para até
  você atualizar o `AD_DC_IP`/`extra_hosts` — considere a seção de alta
  disponibilidade em [03-federacao-ad.md](03-federacao-ad.md#8-alta-disponibilidade-do-ad-opcional-recomendado)

## Onde olhar primeiro, sempre

```powershell
docker compose logs -f keycloak   # 90% dos problemas aparecem aqui
docker compose ps                 # confirma o que está healthy/unhealthy
docker compose config             # confirma que as variáveis resolveram como esperado
```
