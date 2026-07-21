# Certificados TLS

Existe **um** certificado gerenciado por este projeto — não confunda com o
certificado TLS público, que é responsabilidade do proxy externo (fora deste
compose, ver abaixo):

| Certificado | Onde fica | Para que serve |
|---|---|---|
| Certificado da CA do Active Directory | `certs/*.pem` | Fazer o **Keycloak confiar** no certificado LDAPS apresentado pelo Domain Controller |

## 1. TLS público (`https://<KC_HOSTNAME>`)

Este compose **não termina TLS** — o Keycloak fala HTTP puro na rede interna
(`KC_HTTP_ENABLED=true`) e espera um proxy reverso externo na frente cuidando
do certificado público. Como configurar isso depende de onde a stack roda:

- **Coolify**: aponte o domínio do serviço `keycloak` (porta `8080`) nas
  configurações do recurso. Se o host tiver alcance público, a Coolify emite
  e renova um certificado Let's Encrypt automaticamente. Se for ambiente
  **interno** (sem alcance público — o cenário mais comum aqui, dado o uso de
  LDAPS/AD), faça upload do certificado da sua CA corporativa direto na aba de
  domínio/SSL da Coolify, em vez de depender de Let's Encrypt.
- **Nginx/Traefik próprio**: se preferir manter um proxy dedicado fora deste
  compose, aponte-o para `keycloak:8080` na rede `frontend` e termine TLS lá,
  com o certificado da sua CA corporativa.

Em qualquer caso, confirme que `KC_PROXY_TRUSTED_ADDRESSES`
(`docker-compose.yml`) cobre o IP/rede de onde esse proxy fala com o
Keycloak — caso contrário os cabeçalhos `X-Forwarded-*` são ignorados e o
Keycloak não reconhece a conexão como HTTPS.

## 2. Certificado da CA do Active Directory

Esse é o certificado que faz o Keycloak **confiar** no servidor LDAPS do AD
durante o handshake TLS. Sem ele, a federação LDAP falha com erro de
`PKIX path building failed` (ver [06-troubleshooting.md](06-troubleshooting.md)).

### Exportando o certificado da CA do Active Directory

**Opção A — via linha de comando, direto no Domain Controller (Windows):**

```
certutil -ca.cert ad-ca.cer
```

Isso gera um arquivo binário (DER). Converta para PEM (formato que o Keycloak
espera) usando OpenSSL:

```powershell
openssl x509 -inform der -in ad-ca.cer -out ad-ca.pem
```

**Opção B — via MMC (interface gráfica), no Domain Controller:**

1. `mmc.exe` → **File → Add/Remove Snap-in** → **Certificates** → conta do computador
2. **Certificates (Local Computer) → Trusted Root Certification Authorities → Certificates**
3. Ache o certificado da CA raiz do domínio → botão direito → **All Tasks → Export**
4. Escolha o formato **Base-64 encoded X.509 (.CER)** — esse formato já é
   texto/PEM, pode só renomear a extensão para `.pem`

### Instalando no projeto

```
certs/
└── ad-ca.pem
```

O nome do arquivo não importa — `KC_TRUSTSTORE_PATHS=/opt/keycloak/certs`
escaneia o diretório inteiro, recursivamente, incluindo arquivos `.pem`,
`.crt`, `.p12` e `.pfx` (PKCS12 precisa estar **sem senha**).

Se o deploy for via Coolify (Docker Compose), lembre que `certs/` está no
`.gitignore` e não vem com o clone do repositório — copie o arquivo direto no
servidor (aba **Terminal** da Coolify ou SSH), no diretório onde a Coolify
clonou o projeto.

> ⚠️ O truststore é carregado na inicialização do Keycloak. Depois de
> adicionar/trocar um certificado em `certs/`, é preciso reiniciar o container:
> ```powershell
> docker compose restart keycloak
> ```

### Validação de hostname (importante)

O Keycloak valida que o **hostname usado na Connection URL do LDAP** bate com
o CN/SAN do certificado do DC — não basta confiar na CA, o nome também precisa
casar. Veja a seção específica em
[03-federacao-ad.md](03-federacao-ad.md#7-validação-de-hostname-no-ldaps).

## 3. Rotina de renovação

| Certificado | Validade típica | O que fazer ao vencer |
|---|---|---|
| TLS público (Let's Encrypt via Coolify) | 90 dias | Renovado automaticamente pela Coolify |
| TLS público (CA corporativa, via Coolify ou proxy próprio) | Depende da política da empresa | Fazer novo upload do certificado no local onde ele foi configurado |
| CA do Active Directory | Anos (CA raiz normalmente é de longa duração) | Repetir a exportação e `docker compose restart keycloak` |

## Próximo passo

Com os certificados no lugar, siga para
[03-federacao-ad.md](03-federacao-ad.md) (se ainda não configurou a federação)
ou [05-operacao.md](05-operacao.md) para as rotinas do dia a dia.
