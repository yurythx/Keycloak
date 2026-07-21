# Checklist de segurança antes de produção

Use esta lista antes de liberar o Keycloak para autenticar usuários reais.

## Rede e exposição

- [ ] Só o Nginx publica portas no host (`80`/`443`) — confirmado por padrão neste projeto
- [ ] `PROXY_TRUSTED_ADDRESSES` restrito à(s) rede(s) real(is) do proxy, não um range genérico amplo demais
- [ ] Porta de management (`9000`, health/metrics) **não** exposta para fora da rede Docker
- [ ] Firewall entre o host Docker e o Domain Controller libera só o necessário (636/LDAPS, 53/DNS)

## Segredos

- [ ] `secrets/*.txt` gerados com senha forte (32+ caracteres) — não os valores de exemplo
- [ ] `.env` e `secrets/` confirmados fora do controle de versão (`git status` não deve listá-los)
- [ ] Senha do admin do Keycloak trocada manualmente após o primeiro boot (a do `.env`/secret só vale para a criação inicial)
- [ ] MFA (OTP) ativado para a conta de admin do Keycloak
- [ ] Conta de bind do LDAP é uma conta de serviço **read-only**, não uma conta de administrador do domínio

## TLS / Certificados

- [ ] Certificado autoassinado de desenvolvimento **substituído** por um certificado real (CA corporativa ou Let's Encrypt) — ver [04-certificados-tls.md](04-certificados-tls.md)
- [ ] `KC_HOSTNAME` aponta para a URL pública real, com `https://`
- [ ] Federação LDAP usa `ldaps://` (porta 636), nunca `ldap://` simples
- [ ] Certificado da CA do AD instalado em `certs/` e validado com **Test connection** no Admin Console

## Realm e clients

- [ ] Aplicações e usuários finais vivem em um realm próprio, **não** no `master`
- [ ] Cada aplicação tem seu próprio *client*, com *redirect URIs* restritos ao domínio real dela (nada de wildcard `*`)
- [ ] *Client secrets* de clients confidenciais tratados com o mesmo cuidado das senhas deste projeto
- [ ] Fluxos de autenticação (*Authentication Flows*) revisados — em especial *brute force detection* ativado (Realm Settings → Security Defenses)
- [ ] Tempo de vida de sessões e tokens (*Tokens* tab do realm) ajustado à política de segurança da empresa, não deixado no default genérico

## Backup e continuidade

- [ ] Rotina de backup do Postgres agendada e testada (restore já validado ao menos uma vez) — ver [05-operacao.md](05-operacao.md#backup-do-postgres)
- [ ] Backups armazenados fora da mesma máquina/host
- [ ] Se houver mais de um Domain Controller disponível, redundância configurada em `extra_hosts`/`dns` — ver [03-federacao-ad.md](03-federacao-ad.md#8-alta-disponibilidade-do-ad-opcional-recomendado)

## Observabilidade

- [ ] Logs (`json-file` com rotação) acompanhados ou centralizados em alguma stack de observabilidade
- [ ] Métricas Prometheus (`/metrics`) coletadas, com alertas básicos (ex: Keycloak fora do ar, Postgres não saudável)
- [ ] Alertas de tentativas de login malsucedidas em volume anormal (possível força bruta) configurados

## Processo

- [ ] Rodou o passo a passo completo de [02-instalacao.md](02-instalacao.md) do zero em um ambiente de teste antes de repetir em produção
- [ ] Time responsável sabe onde estão os arquivos de secrets e como rotacioná-los ([05-operacao.md](05-operacao.md#rotacionando-senhas))
- [ ] Este checklist revisado por mais de uma pessoa antes do go-live
