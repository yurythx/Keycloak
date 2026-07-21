# Certificados TLS

Existem **dois** certificados diferentes neste projeto — não confunda os dois:

| Certificado | Onde fica | Para que serve |
|---|---|---|
| Certificado TLS do Nginx | `nginx/certs/fullchain.pem` + `privkey.pem` | Servir `https://<KC_HOSTNAME>` aos usuários/navegadores |
| Certificado da CA do Active Directory | `certs/*.pem` | Fazer o **Keycloak confiar** no certificado LDAPS apresentado pelo Domain Controller |

## 1. Certificado TLS do Nginx

### Desenvolvimento / teste

`scripts/generate-secrets.ps1` já gera um certificado autoassinado válido por
365 dias (CN=`auth.local`), se o OpenSSL estiver no PATH. O navegador vai
mostrar aviso de "conexão não segura" — esperado, é autoassinado.

Se preferir gerar manualmente:

```powershell
openssl req -x509 -nodes -days 365 -newkey rsa:2048 `
  -keyout nginx\certs\privkey.pem -out nginx\certs\fullchain.pem `
  -subj "/CN=auth.local" `
  -addext "subjectAltName=DNS:auth.local,DNS:localhost"
```

### Produção — certificado da CA corporativa

Se sua empresa tem uma CA interna (comum em ambientes com Active Directory /
ADCS), gere um certificado para o hostname público do Keycloak (o mesmo valor
de `KC_HOSTNAME`, sem o `https://`) e coloque os arquivos em:

```
nginx/certs/fullchain.pem   # certificado + cadeia intermediária, nessa ordem
nginx/certs/privkey.pem     # chave privada, sem senha
```

Depois de trocar os arquivos:

```powershell
docker compose restart nginx
```

### Produção — Let's Encrypt (se o host for público na internet)

Se o Keycloak vai ser acessado pela internet pública (não só rede interna),
uma opção é usar `certbot` para emitir/renovar automaticamente. Isso está fora
do escopo deste compose (normalmente exige um container `certbot` adicional
com validação HTTP-01 ou DNS-01) — avalie se faz sentido para o seu cenário
antes de adicionar essa peça.

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
| TLS do Nginx (autoassinado de dev) | 365 dias (fixado no script) | Gerar de novo com `generate-secrets.ps1` (apague os arquivos antigos primeiro) |
| TLS do Nginx (CA corporativa) | Depende da política da empresa | Substituir os arquivos e `docker compose restart nginx` |
| CA do Active Directory | Anos (CA raiz normalmente é de longa duração) | Repetir a exportação e `docker compose restart keycloak` |

## Próximo passo

Com os certificados no lugar, siga para
[03-federacao-ad.md](03-federacao-ad.md) (se ainda não configurou a federação)
ou [05-operacao.md](05-operacao.md) para as rotinas do dia a dia.
