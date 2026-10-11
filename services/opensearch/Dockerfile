# OpenSearch for Onyx on Railway (same version as Onyx's docker-compose).
# Starts as root only to fix ownership of the Railway volume, then runs the
# upstream entrypoint as the opensearch user (uid/gid 1000).
FROM opensearchproject/opensearch:3.6.0

USER root
COPY --chmod=755 railway-start.sh /usr/local/bin/railway-start.sh

ENTRYPOINT ["/usr/local/bin/railway-start.sh"]
CMD ["opensearch"]
