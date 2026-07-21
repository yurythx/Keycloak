# Operação do dia a dia

## Comandos essenciais

```powershell
# Status de todos os serviços (procure por "healthy")
docker compose ps

# Logs em tempo real de um serviço
docker compose logs -f keycloak
docker compose logs -f postgres
docker compose logs -f nginx

# Reiniciar um serviço específico (ex: depois de trocar um certificado)
docker compose restart nginx
docker compose restart keycloak

# Parar/subir a stack inteira
docker compose down
docker compose up -d
```

## Backup do Postgres

O estado inteiro do Keycloak (realms, usuários locais, clients, configurações,
sessões, log de eventos) vive no volume `postgres_data`. Faça backup lógico
regularmente:

```powershell
docker compose exec postgres pg_dump -U keycloak_user keycloak > backup_$(Get-Date -Format "yyyyMMdd_HHmmss").sql
```

Automatize isso com o **Agendador de Tarefas do Windows** rodando o comando
acima diariamente, guardando os arquivos em um local com backup próprio
(rede, storage externo, etc. — não deixe os `.sql` só na mesma máquina).

### Restaurar

```powershell
# Com a stack no ar, mas o Keycloak parado para evitar escrita concorrente
docker compose stop keycloak

Get-Content backup_20260101_120000.sql | docker compose exec -T postgres psql -U keycloak_user -d keycloak

docker compose start keycloak
```

## Atualizando a versão do Keycloak

1. Troque a tag `26.0` para a nova versão nas duas linhas `FROM` do `Dockerfile`
2. Leia o changelog/upgrade guide oficial da versão de destino — migrações de
   schema geralmente rodam automaticamente no boot, mas mudanças de opções de
   configuração (como já aconteceu de `KC_PROXY` para `KC_PROXY_HEADERS`) podem
   exigir ajustes no `docker-compose.yml`
3. **Faça backup do Postgres antes** (seção acima)
4. Reconstrua e suba:
   ```powershell
   docker compose up -d --build keycloak
   ```
5. Acompanhe `docker compose logs -f keycloak` até o boot terminar e confirme
   login/federação LDAP normalmente

## Rotacionando senhas

### Senha do admin do Keycloak

Trocar o arquivo `secrets/kc_admin_password.txt` **não tem efeito** depois do
primeiro boot (`KC_BOOTSTRAP_ADMIN_PASSWORD` só é lido na criação do realm
master). Para trocar de fato:

- Admin Console → **Users** → conta do admin → **Credentials** → **Reset password**
- Ou via `kcadm.sh` dentro do container, se preferir automatizar

### Senha do Postgres

Aqui sim precisa dos dois passos — trocar o arquivo **e** o valor já persistido
no banco:

```powershell
# 1. Gere/edite o novo valor
"nova-senha-bem-forte-aqui" | Out-File -NoNewline -Encoding utf8 secrets\postgres_password.txt

# 2. Atualize dentro do Postgres (ele já precisa estar no ar com a senha antiga)
docker compose exec postgres psql -U keycloak_user -d keycloak -c "ALTER USER keycloak_user WITH PASSWORD 'nova-senha-bem-forte-aqui';"

# 3. Recrie o Keycloak para ele ler a nova senha do secret file
docker compose up -d --force-recreate keycloak
```

## Observabilidade

- **Health**: `KC_HEALTH_ENABLED=true` expõe `/health/ready` e `/health/live`
  na porta de management (`9000`, só acessível de dentro da rede Docker —
  é o que o `healthcheck` do compose usa)
- **Métricas Prometheus**: `KC_METRICS_ENABLED=true` expõe `/metrics` também
  na porta `9000`. Para coletar com um Prometheus externo, adicione um scrape
  config apontando para o container (ex: via uma rede compartilhada ou
  publicando a porta 9000 **apenas** para a rede de observabilidade, nunca
  para o host público)

Exemplo de `scrape_config` (assumindo Prometheus na mesma rede Docker):

```yaml
scrape_configs:
  - job_name: keycloak
    metrics_path: /metrics
    static_configs:
      - targets: ["keycloak_server:9000"]
```

## Logs

Todos os serviços já usam `json-file` com rotação (`max-size: 10m`,
`max-file: 3`) — evita que os logs encham o disco do host sozinhos. Para
centralizar em uma stack de observabilidade (ELK, Loki, etc.), redirecione o
driver de logging conforme a ferramenta escolhida.

## Escalando para múltiplas réplicas (avançado)

O compose atual sobe **um único** container de Keycloak. Isso é adequado para
a maioria dos ambientes on-premise. Se for necessário rodar múltiplas réplicas
para alta disponibilidade, o Keycloak (Quarkus) precisa de configuração
adicional de cache distribuído (Infinispan/JGroups) para sincronizar sessões
entre nós — isso está fora do escopo deste projeto base e deve ser avaliado
como uma evolução futura, não uma mudança trivial de `replicas: N`.

## Próximo passo

Problemas na inicialização ou na federação? Veja
[06-troubleshooting.md](06-troubleshooting.md).
