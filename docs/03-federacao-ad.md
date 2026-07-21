# Federação com Active Directory (LDAPS)

A federação é configurada **dentro do Keycloak**, depois que a stack já está no
ar — não é um passo do `docker-compose.yml`. Faça isso no realm de produção
que você criou em [02-instalacao.md](02-instalacao.md#8-criar-um-realm-de-produção-não-usar-o-master), não no `master`.

## 1. Pré-requisitos no lado do Active Directory

- **Conta de serviço dedicada** para o bind do Keycloak, só com permissão de
  leitura no diretório. Nunca use uma conta de administrador do domínio aqui —
  se o Keycloak for comprometido, o blast radius fica limitado a leitura do AD
- Descubra o **Distinguished Name (DN)** dessa conta, ex:
  `CN=svc-keycloak,OU=ServiceAccounts,DC=meudominio,DC=local`
- Descubra o **DN da OU** onde ficam os usuários que vão logar, ex:
  `OU=Usuarios,DC=meudominio,DC=local`
- Confirme que o DC aceita LDAPS na porta 636 (não LDAP simples na 389 —
  ver a nota sobre segurança abaixo)

## 2. Adicionar o provider LDAP

No Admin Console, dentro do realm correto:

**User Federation → Add provider... → ldap**

Preencha os campos:

| Campo | Valor sugerido | Observação |
|---|---|---|
| Console Display Name | `Active Directory` | Só um nome de exibição |
| Vendor | `Active Directory` | Ajusta defaults de atributos automaticamente |
| Username LDAP attribute | `sAMAccountName` | Como os usuários digitam o login |
| RDN LDAP attribute | `cn` | |
| UUID LDAP attribute | `objectGUID` | Identificador único e estável do AD |
| User Object Classes | `person, organizationalPerson, user` | |
| **Connection URL** | `ldaps://dc01.meudominio.local:636` | **Use o hostname (`AD_DC_HOSTNAME`), nunca o IP** — ver seção de validação de hostname abaixo |
| Enable StartTLS | `Off` | Já estamos usando LDAPS nativo na 636, não precisa de StartTLS sobre a 389 |
| Users DN | `OU=Usuarios,DC=meudominio,DC=local` | |
| Bind Type | `simple` | |
| Bind DN | `CN=svc-keycloak,OU=ServiceAccounts,DC=meudominio,DC=local` | A conta de serviço |
| Bind Credential | *(senha da conta de serviço)* | Guarde essa senha com o mesmo cuidado dos outros segredos do projeto |
| **Edit Mode** | `READ_ONLY` | Recomendado — o Keycloak nunca escreve de volta no AD |
| Sync Registrations | `Off` | Novos usuários continuam sendo criados no AD, não no Keycloak |

## 3. Testar antes de salvar

Use os botões no topo do formulário:

1. **Test connection** — valida que o Keycloak alcança o DC na porta 636 e que
   o certificado é confiável (usa o `KC_TRUSTSTORE_PATHS` configurado)
2. **Test authentication** — valida que o Bind DN/Bind Credential conseguem
   autenticar no AD

Se algum desses falhar, veja [06-troubleshooting.md](06-troubleshooting.md#federação-ldap).

## 4. Sincronização

Em **Synchronization Settings**:

- **Import Users**: `On` — importa o usuário para o Keycloak no primeiro login
  (fica um "cache" local com referência ao AD, a senha nunca é copiada)
- **Periodic Full Sync**: opcional. Ative se quiser que usuários apareçam no
  Keycloak antes do primeiro login (útil para pré-provisionar acesso a
  aplicações). Um `Full Sync Period` de `86400` (1x por dia) é um ponto de
  partida razoável para a maioria dos ambientes
- **Periodic Changed Users Sync**: opcional, sincroniza só deltas com mais
  frequência (ex: a cada `3600` segundos)

## 5. Mapear grupos do AD para autorização no Keycloak

Sem isso, o Keycloak só sabe *quem* o usuário é — não *a que grupos ele pertence*.
Para propagar grupos do AD (e usá-los em *role mappings* das suas aplicações):

1. Volta na tela do provider LDAP recém-criado → aba **Mappers**
2. **Add mapper** → tipo `group-ldap-mapper`
3. Configure:
   - **LDAP Groups DN**: `OU=Grupos,DC=meudominio,DC=local`
   - **Group Name LDAP Attribute**: `cn`
   - **Group Object Classes**: `group`
   - **Membership LDAP Attribute**: `member`
   - **Mode**: `READ_ONLY`
4. Salve e rode **Sync LDAP Groups To Keycloak** (botão na própria tela) para
   trazer os grupos existentes imediatamente

Depois disso, os grupos do AD aparecem em **Groups** no Keycloak e podem
receber *role mappings* normalmente, que se propagam para os tokens JWT.

## 6. Segurança: por que LDAPS e não LDAP simples

Se o *federation provider* for configurado com `ldap://` (porta 389) em vez de
`ldaps://` (porta 636), as credenciais dos usuários do AD trafegam **em texto
claro** dentro da rede Docker durante o bind. Sempre confirme que a
**Connection URL** começa com `ldaps://`. Esse projeto já assume LDAPS —
é por isso que o `KC_TRUSTSTORE_PATHS` e o certificado da CA em `certs/`
existem (ver [04-certificados-tls.md](04-certificados-tls.md)).

## 7. Validação de hostname no LDAPS

O Keycloak faz *strict hostname checking* na conexão LDAPS: o CN ou algum SAN
(Subject Alternative Name) do certificado apresentado pelo DC precisa bater
com o hostname usado na **Connection URL**. É por isso que:

- A Connection URL usa `AD_DC_HOSTNAME` (ex: `dc01.meudominio.local`), não o IP
- O `docker-compose.yml` injeta esse hostname no `/etc/hosts` do container
  via `extra_hosts`, apontando para `AD_DC_IP`

Se o certificado do DC só tiver um outro nome (ex: outro FQDN, ou nome curto
NetBIOS), ajuste a Connection URL e o `extra_hosts` para usar exatamente esse
nome.

## 8. Alta disponibilidade do AD (opcional, recomendado)

O compose atual aponta para **um único** Domain Controller. Se ele cair, a
federação LDAP para de funcionar (novos logins de usuários do AD falham,
embora sessões já ativas continuem válidas até expirar). Se houver mais de um
DC no ambiente, considere:

- Adicionar um segundo `extra_hosts` apontando para o DC secundário
- Ou, mais robusto: publicar um registro DNS round-robin/SRV que já resolva
  para múltiplos DCs, e usar esse nome na Connection URL

## Próximo passo

Com a federação testada, siga para [05-operacao.md](05-operacao.md) para
rotinas de backup, logs e atualização, ou para
[07-seguranca-checklist.md](07-seguranca-checklist.md) antes de liberar para
os usuários finais.
