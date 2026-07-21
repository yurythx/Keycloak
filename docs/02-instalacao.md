# Instalação — passo a passo completo

## 1. Pré-requisitos

### Software

| Ferramenta | Versão mínima | Verificar com |
|---|---|---|
| Docker Engine | 24.x | `docker --version` |
| Docker Compose | v2 (plugin `compose`) | `docker compose version` |
| PowerShell | 5.1 (já vem no Windows) | `$PSVersionTable.PSVersion` |
| OpenSSL (opcional, só para gerar cert de teste) | qualquer 1.1+ | `openssl version` |

### Rede / Firewall

| Origem | Destino | Porta | Motivo |
|---|---|---|---|
| Usuários/aplicações | Host onde roda o Nginx | 443/tcp (e 80/tcp para redirect) | Login, emissão de tokens |
| Container Keycloak | Domain Controller do AD | 636/tcp (LDAPS) | Federação de identidade |
| Container Keycloak | Domain Controller do AD | 53/tcp+udp (DNS) | Resolução do FQDN do DC |
| — | Postgres | 5432 | **Não precisa** — fica só na rede interna `backend` |

Se houver firewall entre o host Docker e o Domain Controller, libere a 636/tcp
(e a 53 se você depender do DNS do domínio) antes de continuar.

### Informações que você vai precisar antes de começar

- [ ] Hostname público que os usuários vão usar para autenticar (ex: `auth.suaempresa.com`)
- [ ] IP e FQDN do Domain Controller (ex: `192.168.1.10` / `dc01.meudominio.local`)
- [ ] Certificado da CA que assinou o certificado LDAPS do AD (ver [04-certificados-tls.md](04-certificados-tls.md))
- [ ] Uma conta de serviço no AD com permissão de **leitura** (bind account), sem privilégios de admin

## 2. Configurar variáveis de ambiente

```powershell
Copy-Item .env.example .env
notepad .env
```

Referência completa de cada variável:

| Variável | Obrigatória | Exemplo | Descrição |
|---|---|---|---|
| `POSTGRES_DB` | não (default `keycloak`) | `keycloak` | Nome do banco criado no Postgres |
| `POSTGRES_USER` | não (default `keycloak_user`) | `keycloak_user` | Usuário dono do banco |
| `KC_BOOTSTRAP_ADMIN_USERNAME` | não (default `kc_admin`) | `kc_admin` | Usuário admin criado **apenas no primeiro boot** do realm master |
| `KC_HOSTNAME` | **sim** | `https://auth.suaempresa.com` | URL pública usada nos tokens/issuers — precisa bater com o que o Nginx serve |
| `KC_LOG_LEVEL` | não (default `INFO`) | `INFO`, `DEBUG`, `WARN` | Verbosidade de log |
| `PROXY_TRUSTED_ADDRESSES` | não (default `172.16.0.0/12`) | CIDR da rede Docker/host | De onde o Keycloak aceita confiar nos cabeçalhos `X-Forwarded-*` |
| `AD_DOMAIN` | **sim** | `meudominio.local` | FQDN do domínio, usado para resolução de nomes dentro do container |
| `AD_DC_HOSTNAME` | **sim** | `dc01.meudominio.local` | Hostname exato do Domain Controller — precisa bater com o CN/SAN do certificado LDAPS |
| `AD_DC_IP` | **sim** | `192.168.1.10` | IP do Domain Controller |

As senhas (Postgres e admin do Keycloak) **não ficam no `.env`** — são geradas
como arquivos separados no passo seguinte.

## 3. Gerar as senhas e o certificado de desenvolvimento

```powershell
.\scripts\generate-secrets.ps1
```

O script:

1. Gera uma senha aleatória forte (32 caracteres) em `secrets/postgres_password.txt`
2. Gera outra em `secrets/kc_admin_password.txt`
3. Se o OpenSSL estiver no PATH, gera um certificado TLS autoassinado em
   `nginx/certs/fullchain.pem` / `privkey.pem` (**apenas para desenvolvimento** —
   troque por um certificado real antes de produção, ver [04-certificados-tls.md](04-certificados-tls.md))
4. Não sobrescreve nada que já exista — seguro rodar mais de uma vez

Se preferir gerar manualmente (sem o script):

```powershell
# Senha do Postgres
-join ((48..57)+(65..90)+(97..122)|Get-Random -Count 32|%{[char]$_}) | Out-File -NoNewline -Encoding utf8 secrets\postgres_password.txt

# Senha do admin do Keycloak
-join ((48..57)+(65..90)+(97..122)|Get-Random -Count 32|%{[char]$_}) | Out-File -NoNewline -Encoding utf8 secrets\kc_admin_password.txt
```

## 4. Colocar o certificado da CA do Active Directory

Copie o certificado da CA (formato `.pem` ou `.crt`, base64) para a pasta `certs/`:

```
certs/
└── ad-ca.pem
```

Qualquer nome de arquivo serve — o Keycloak escaneia o diretório inteiro
(`KC_TRUSTSTORE_PATHS=/opt/keycloak/certs`) recursivamente.

Como extrair esse certificado do seu AD: ver [04-certificados-tls.md](04-certificados-tls.md#exportando-o-certificado-da-ca-do-active-directory).

## 5. Subir a stack

```powershell
docker compose up -d --build
```

Isso vai, na ordem:

1. Construir a imagem customizada do Keycloak (`Dockerfile` → `kc.sh build`)
2. Subir o Postgres e esperar o `healthcheck` (`pg_isready`) ficar OK
3. Subir o Keycloak (só depois do Postgres estar saudável — `depends_on: condition: service_healthy`)
4. Subir o Nginx (só depois do Keycloak responder `/health/ready` — pode levar 30–60s na primeira vez)

## 6. Acompanhar a inicialização

```powershell
docker compose logs -f keycloak
```

Procure pela linha `Keycloak <versão> on JVM ... started in ...` — é o sinal de
que o servidor terminou de subir.

Verifique o status de todos os containers:

```powershell
docker compose ps
```

Todos devem aparecer como `running` / `healthy`.

## 7. Primeiro acesso ao Admin Console

1. Recupere a senha gerada:
   ```powershell
   Get-Content secrets\kc_admin_password.txt
   ```
2. Acesse `https://<KC_HOSTNAME>/admin`
3. Login com o usuário de `KC_BOOTSTRAP_ADMIN_USERNAME` (default `kc_admin`) e a senha acima
4. **Recomendado:** troque a senha imediatamente pelo próprio Admin Console
   (Users → kc_admin → Credentials) e considere ativar um segundo fator (OTP)
   para essa conta, já que ela tem acesso total ao realm `master`

> ⚠️ As variáveis `KC_BOOTSTRAP_ADMIN_USERNAME`/`PASSWORD` só são lidas **na
> primeira inicialização** do realm `master`. Mudar o valor no `.env`/`secrets/`
> depois não tem efeito nenhum — a troca de senha do admin é feita pelo Admin
> Console (ou `kcadm.sh`), não reiniciando o container.

## 8. Criar um realm de produção (não usar o `master`)

O realm `master` é reservado para administração da própria instância do
Keycloak. Aplicações e usuários finais devem viver em um realm separado:

1. Admin Console → menu do realm (canto superior esquerdo) → **Create Realm**
2. Dê um nome (ex: `suaempresa`)
3. Configure esse realm — não o `master` — com a federação LDAP
   ([03-federacao-ad.md](03-federacao-ad.md)) e os *clients* das suas aplicações

## 9. Checklist de saída desta etapa

- [ ] `docker compose ps` mostra todos os serviços `healthy`
- [ ] Login no Admin Console funcionou com a senha gerada
- [ ] Senha do admin trocada / MFA considerado
- [ ] Realm de produção criado (separado do `master`)
- [ ] Certificado da CA do AD presente em `certs/`

Próximo passo: [docs/03-federacao-ad.md](03-federacao-ad.md) para conectar esse
realm ao Active Directory.
