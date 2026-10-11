# Notice

## Upstream software

- **Onyx** — MIT (Expat) for content outside the `ee` directories; `backend/ee`, `web/src/app/ee` and `web/src/ee` are under the Onyx Enterprise License (enterprise features stay disabled: `ENABLE_PAID_ENTERPRISE_EDITION_FEATURES=false`). Copyright (c) 2023-present DanswerAI, Inc. Images used unmodified: `onyxdotapp/onyx-backend:v4.9.0`, `onyxdotapp/onyx-web-server:v4.9.0`, `onyxdotapp/onyx-model-server:v4.9.0` (published by Onyx on Docker Hub).
- **OpenSearch** — Apache-2.0. Image `opensearchproject/opensearch:3.6.0`, extended only with a start script.
- **nginx** — BSD-2-Clause. Image `nginx:1.30.5` (Docker official image), extended with a config template.
- **SeaweedFS** — Apache-2.0. Image `chrislusf/seaweedfs:4.48`.
- **PostgreSQL** — PostgreSQL License. Image `ghcr.io/railwayapp-templates/postgres-ssl:18` (Railway).
- **Redis** — Redis 8 is available under RSALv2/SSPLv1/AGPLv3. Image `redis:8.2` (Docker official image).

## Verified against

| What | Source | Version / ref | Checked |
|---|---|---|---|
| Services, OpenSearch version, start commands, MinIO profile, code-interpreter | https://github.com/onyx-dot-app/onyx/blob/v4.9.0/deployment/docker_compose/docker-compose.yml | v4.9.0 | 2026-10-10 |
| Environment variables and defaults | `deployment/docker_compose/env.template`, `backend/onyx/configs/app_configs.py`, `backend/shared_configs/configs.py` | v4.9.0 | 2026-10-10 |
| Resource limits | `deployment/docker_compose/docker-compose.resources.yml` | v4.9.0 | 2026-10-10 |
| nginx routing | `deployment/data/nginx/app.conf.template`, `run-nginx.sh` | v4.9.0 | 2026-10-10 |
| S3 file store forces path-style with a custom endpoint | `backend/onyx/file_store/file_store.py` | v4.9.0 | 2026-10-10 |
| Model server bind address / app object | `backend/model_server/main.py`, `backend/Dockerfile.model_server` | v4.9.0 | 2026-10-10 |
| Web server `HOSTNAME`, public assets; `/api` proxy disabled in production | `web/Dockerfile`, `web/src/app/api/[...path]/route.ts` | v4.9.0 | 2026-10-10 |
| Background worker set | `backend/supervisord.conf` | v4.9.0 | 2026-10-10 |
| SeaweedFS env-based S3 credentials, `/healthz`, entrypoint | https://github.com/seaweedfs/seaweedfs (`weed/s3api/auth_credentials.go`, `weed/s3api/s3api_server.go`, `docker/entrypoint.sh`) | 4.48 | 2026-10-10 |
| Railway Bucket addressing style | https://docs.railway.com/storage-buckets | docs | 2026-10-10 |
| Railway postgres-ssl entrypoint (`tini`, `wrapper.sh`) | https://github.com/railwayapp-templates/postgres-ssl | main | 2026-10-10 |

## Adapted code

- `services/nginx/templates/default.conf.template` is adapted from `deployment/data/nginx/app.conf.template` of onyx-dot-app/onyx v4.9.0, Copyright (c) 2023-present DanswerAI, Inc., MIT License. Changes: request-time DNS resolution via variables, IPv6 listener, `X-Forwarded-Proto` from Railway's edge, merged SAML/SCIM locations, MCP includes removed. The MIT permission notice applies to that file.
- `services/nginx/Dockerfile`, `services/opensearch/Dockerfile` and `services/opensearch/railway-start.sh` were written for this template.
- Postgres and Redis definitions come from this repository's `_railway-base` files (Postgres start command extended).

## Reference only (not copied)

- Railway marketplace templates `onyx`, `onyx-lite`, `onyx-lite-chat-postgres`: configuration read for ideas; no text or files copied. No license is attached to them.

## Trademarks

Onyx is a trademark of DanswerAI, Inc.; OpenSearch, nginx, SeaweedFS, PostgreSQL, Redis and the named SaaS products belong to their respective owners. This is a community template and is not affiliated with or endorsed by Onyx.
