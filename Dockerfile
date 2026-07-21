# =============================================================================
# Build otimizado do Keycloak (padrão recomendado pela documentação oficial
# para produção: https://www.keycloak.org/server/containers#_creating_a_customized_and_optimized_container_image)
#
# O comando `kc.sh build` "fixa" as opções de build (tipo de banco, health,
# métricas) dentro da imagem, permitindo `start --optimized` no runtime, que
# pula a fase de re-augmentation e reduz o tempo de boot.
# =============================================================================
FROM quay.io/keycloak/keycloak:26.0 AS builder

# Opções de build-time (ficam fixas na imagem gerada)
ENV KC_DB=postgres
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true

WORKDIR /opt/keycloak
RUN /opt/keycloak/bin/kc.sh build

# -----------------------------------------------------------------------------
FROM quay.io/keycloak/keycloak:26.0

COPY --from=builder /opt/keycloak/ /opt/keycloak/

# Wrapper de entrypoint: dá suporte a variáveis "_FILE" (Docker secrets),
# já que o Keycloak não tem suporte nativo a esse padrão (ao contrário da
# imagem oficial do Postgres).
USER root
COPY entrypoint-secrets.sh /opt/keycloak/bin/entrypoint-secrets.sh
RUN chmod +x /opt/keycloak/bin/entrypoint-secrets.sh
USER 1000

ENTRYPOINT ["/opt/keycloak/bin/entrypoint-secrets.sh"]
# Default caso o orquestrador não informe um comando (ex.: deploy fora do
# docker-compose.yml, que normalmente sobrescreve isto com "start --optimized").
CMD ["start", "--optimized"]
