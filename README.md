# Keycloak — Autenticação Centralizada

Stack de produção para centralizar a autenticação de todos os usuários da empresa
em um único ponto: **Postgres 16** + **Keycloak 26 (build otimizado)** + **Nginx
(TLS termination)**, com federação de identidade contra o **Active Directory via LDAPS**.

```
                    ┌───────────────────────────────────────────────┐
                    │              Rede "frontend"                  │
  Usuários / Apps ──┼──▶ Nginx :443 (TLS) ──▶ Keycloak :8080         │
                    │                              │                │
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

Só o **Nginx** publica portas no host. Keycloak e Postgres só são alcançáveis
pela rede interna do Docker.

## Documentação

| Documento | Conteúdo |
|---|---|
| [docs/01-arquitetura.md](docs/01-arquitetura.md) | Como cada peça se encaixa e por quê |
| [docs/02-instalacao.md](docs/02-instalacao.md) | Passo a passo completo de instalação |
| [docs/03-federacao-ad.md](docs/03-federacao-ad.md) | Configurar o Keycloak para autenticar contra o Active Directory |
| [docs/04-certificados-tls.md](docs/04-certificados-tls.md) | Certificado do Nginx e confiança no CA do AD |
| [docs/05-operacao.md](docs/05-operacao.md) | Logs, backup/restore, atualização de versão, rotação de senhas |
| [docs/06-troubleshooting.md](docs/06-troubleshooting.md) | Erros comuns e como resolver |
| [docs/07-seguranca-checklist.md](docs/07-seguranca-checklist.md) | Checklist de hardening antes de ir para produção |

## Quickstart

```powershell
# 1. Configurar variáveis de ambiente
Copy-Item .env.example .env
notepad .env

# 2. Gerar senhas fortes e certificado de teste
.\scripts\generate-secrets.ps1

# 3. Colocar o certificado da CA do Active Directory em certs/
#    (ver docs/04-certificados-tls.md)

# 4. Subir a stack
docker compose up -d --build

# 5. Acompanhar a inicialização
docker compose logs -f keycloak
```

Acesse `https://<KC_HOSTNAME>/admin` com o usuário de `KC_BOOTSTRAP_ADMIN_USERNAME`
e a senha gerada em `secrets/kc_admin_password.txt`.

Para o passo a passo completo — incluindo pré-requisitos, configuração detalhada
de cada variável e validação — siga [docs/02-instalacao.md](docs/02-instalacao.md).

## Estrutura do repositório

```
.
├── docker-compose.yml       # postgres + keycloak (build otimizado) + nginx
├── Dockerfile               # kc.sh build → start --optimized
├── entrypoint-secrets.sh    # suporte a "_FILE" (Docker secrets) no Keycloak
├── .env.example             # variáveis a configurar (copiar para .env)
├── nginx/nginx.conf         # TLS termination + cabeçalhos X-Forwarded-*
├── secrets/                 # senhas geradas (gitignorado)
├── certs/                   # CA do Active Directory para LDAPS (gitignorado)
├── scripts/generate-secrets.ps1
└── docs/                    # documentação detalhada (ver tabela acima)
```
