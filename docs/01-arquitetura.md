# Arquitetura

## Visão geral

```
                    ┌───────────────────────────────────────────────┐
                    │              Rede "frontend"                  │
  Usuários / Apps ──┼──▶ Nginx :443 (TLS) ──▶ Keycloak :8080         │
        (443/80)    │                              │                │
                    └──────────────────────────────┼────────────────┘
                                                    │
                    ┌───────────────────────────────┼────────────────┐
                    │           Rede "backend" (internal, sem saída) │
                    │                              ▼                │
                    │                        Postgres :5432          │
                    └─────────────────────────────────────────────────┘
                                                    │
                                          Keycloak ──┴──▶ AD / DC (LDAPS :636)
```

## Componentes

### Nginx (`keycloak_proxy`)

Único serviço com portas publicadas no host (`80` e `443`). Responsabilidades:

- Terminar TLS (o certificado real da empresa fica aqui, não no Keycloak)
- Redirecionar `80 → 443`
- Injetar os cabeçalhos `X-Forwarded-For` / `X-Forwarded-Proto` / `X-Forwarded-Host`
  que o Keycloak usa para saber que está atrás de um proxy HTTPS

Fica na rede `frontend`. Não tem acesso à rede `backend` (não enxerga o Postgres).

### Keycloak (`keycloak_server`)

- Roda a imagem **customizada** construída pelo `Dockerfile` deste projeto
  (build otimizado via `kc.sh build`, iniciado com `start --optimized`)
- **Não publica porta nenhuma no host** — só é alcançável pelo Nginx (rede `frontend`)
  e fala com o Postgres pela rede `backend`
- Fala HTTP puro internamente (`KC_HTTP_ENABLED=true`); confia no Nginx para TLS
  e valida a origem através de `KC_PROXY_TRUSTED_ADDRESSES`
- Tem acesso de rede ao Active Directory via `extra_hosts`/`dns` (necessário para
  resolver o FQDN do Domain Controller e abrir a conexão LDAPS na porta 636)

### Postgres (`keycloak_db`)

- Guarda todo o estado do Keycloak: realms, usuários locais, clients, sessões, eventos
- Rede `backend` está marcada como `internal: true` — o container **não tem rota
  de saída para a internet**, nem para resolver DNS externo. Mesmo que alguém
  comprometesse o container, ele não consegue exfiltrar dados nem baixar payloads
- Sem porta publicada no host

### Active Directory (externo à stack)

O Keycloak não guarda as senhas dos usuários do domínio — ele delega a autenticação
ao AD via **LDAP Federation** (LDAPS, porta 636). Ver [03-federacao-ad.md](03-federacao-ad.md).

## Por que cada decisão de design

| Decisão | Motivo |
|---|---|
| `start --optimized` (build customizado) em vez de `start-dev` | `start-dev` desabilita proteções de produção (não exige HTTPS, reconstrói configuração a cada boot) e é mais lento para subir |
| Senhas via `secrets/*.txt` + variáveis `_FILE` | Evita senha em texto plano visível em `docker inspect`, no histórico do shell ou no próprio `docker-compose.yml` |
| `entrypoint-secrets.sh` | O Keycloak não suporta nativamente o padrão `_FILE` (diferente da imagem oficial do Postgres) — o wrapper resolve isso lendo o arquivo antes de iniciar o `kc.sh` |
| Nginx na frente, Keycloak sem porta publicada | TLS termina em um único ponto auditável; Keycloak e Postgres ficam inacessíveis diretamente da rede externa |
| Rede `backend` como `internal: true` | Isola o banco de dados de qualquer tentativa de acesso externo, mesmo em caso de comprometimento de outro container |
| `KC_TRUSTSTORE_PATHS=/opt/keycloak/certs` | Faz o Keycloak confiar no CA interno do AD para validar o certificado apresentado no handshake LDAPS |
| `KC_PROXY_HEADERS=xforwarded` + `KC_HTTP_ENABLED=true` | Substitui o antigo `KC_PROXY=edge`, **removido no Keycloak 26.0** — o Keycloak roda em HTTP puro internamente e confia nos cabeçalhos `X-Forwarded-*` do Nginx |
| `KC_PROXY_TRUSTED_ADDRESSES` | Sem restringir isso, qualquer cliente poderia forjar cabeçalhos `X-Forwarded-*` e enganar o Keycloak sobre o IP/protocolo de origem real |
| Healthcheck via `/dev/tcp` (bash) em vez de `curl` | A imagem base do Keycloak não inclui `curl`; o endpoint `/health/ready` fica no **management port 9000** a partir do Keycloak 24+ |
| `mem_limit`/`cpus` em vez de `deploy.resources.limits` | `deploy.resources` só é respeitado de forma consistente em Swarm; para `docker compose up` "normal" (sem swarm), as chaves de serviço (`mem_limit`, `cpus`) funcionam de forma previsível em qualquer versão do Compose v2 |

## Fluxo de login (usuário final)

1. Usuário acessa uma aplicação que usa OIDC/SAML apontando para o realm do Keycloak
2. A aplicação redireciona o navegador para `https://<KC_HOSTNAME>/realms/<realm>/protocol/openid-connect/auth`
3. Esse tráfego chega no Nginx (TLS), que repassa para o Keycloak via HTTP interno
4. Se o usuário pertence à federação LDAP, o Keycloak faz **bind** no AD (LDAPS) para
   validar usuário/senha — a senha nunca é armazenada no Postgres do Keycloak
5. Keycloak emite os tokens (JWT) e redireciona de volta para a aplicação

## Próximo passo

Siga [docs/02-instalacao.md](02-instalacao.md) para subir a stack do zero.
