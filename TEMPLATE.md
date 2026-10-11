# Onyx v4 Enterprise AI Search — Railway template spec

## Listing

- **Name:** Onyx v4 Enterprise AI Search (LISTINGS.md name with the pinned major version inserted; Onyx tags releases `v4.x.y`)
- **Description (78 chars):** Ask questions across Slack, Drive, Confluence and more. Self-hosted AI search. (unchanged)
- **Category:** AI/ML
- **Tags:** onyx, enterprise-search, rag, ai-chat, opensearch, connectors, llm

## Base market template

- **Chosen base: `onyx` "Onyx"** (4 active / 24 projects): the only market template with the full stack (api-server, background, web-server, both model servers, OpenSearch, Postgres, Redis, nginx, object storage). Kept: the service split, model-server/OpenSearch wiring, OpenSearch ownership fix (run as root, drop to uid 1000), nginx route layout, generated `USER_AUTH_SECRET` / `ENCRYPTION_KEY_SECRET`.
- Fixed from that base: v4.8.1 → v4.9.0; MinIO replaced; nginx config passed through an env var and reloaded in a loop (now a small image with request-time DNS resolution); listeners on `0.0.0.0` (unreachable over IPv6-only private networking); no volume-backed Redis; model servers forced to run as root only to write a cache volume.
- `onyx-lite` (Caddy + api + web + Postgres) and `onyx-lite-chat-postgres`: "Onyx Lite" mode with `DISABLE_VECTOR_DB=true`, `DISABLE_MODEL_SERVER=true` — no connectors or document search, so they cannot deliver the listing ("ask questions across Slack, Drive, Confluence"). Took the observation that Railway private DNS needs IPv6-capable listeners.
- `_upstream`: none for this app.

**Search index decision:** Onyx v4.9.0's `deployment/docker_compose/docker-compose.yml` uses **OpenSearch 3.6.0** as the document index (Vespa is gone from the default stack). The template follows it with the same pinned version.

**File store decision:** Onyx's S3 file store (`backend/onyx/file_store/file_store.py`) hardcodes `addressing_style: "path"` whenever `S3_ENDPOINT_URL` is set. Railway Buckets use virtual-hosted-style URLs (new Tigris-backed buckets reject path-style requests), so a Railway Bucket cannot be used without patching Onyx. Per the package standard the template uses **SeaweedFS** (S3 gateway, volume-backed) instead of MinIO. Onyx's alternative `FILE_STORE_BACKEND=postgres` remains available (see README).

## Pinned versions

| Service | Image / source | Tag | Release date | Checked |
|---|---|---|---|---|
| api-server, background | `onyxdotapp/onyx-backend` | `v4.9.0` | 2026-10-07 | 2026-10-10 |
| web-server | `onyxdotapp/onyx-web-server` | `v4.9.0` | 2026-10-07 | 2026-10-10 |
| inference-model-server, indexing-model-server | `onyxdotapp/onyx-model-server` | `v4.9.0` | 2026-10-07 | 2026-10-10 |
| opensearch | Dockerfile `services/opensearch` (`FROM opensearchproject/opensearch:3.6.0`) | `3.6.0` (upstream pin) | 2026-05-15 | 2026-10-10 |
| nginx | Dockerfile `services/nginx` (`FROM nginx:1.30.5`, stable line) | `1.30.5` | 2026 | 2026-10-10 |
| SeaweedFS | `chrislusf/seaweedfs` | `4.48` | 2026-09-28 | 2026-10-10 |
| Postgres | `ghcr.io/railwayapp-templates/postgres-ssl` | `18` | Railway base | 2026-10-10 |
| Redis | `redis` | `8.2` | Railway base | 2026-10-10 |

`v4.9.0` is GitHub's latest release; `v4.8.5` (published a day later) is a patch on the older 4.8 line. Upstream compose uses `postgres:15.2-alpine` and `redis:7.4-alpine`; the template uses the Railway base Postgres 18 and Redis 8.2.

## Architecture

```
                             HTTPS (public domain)
                                     |
                               [nginx :80]
                 /api, /openapi.json, |  everything else
                 /auth/saml, /scim    |
                 v                    v
          [api-server :8080] <--- [web-server :3000] (SSR via INTERNAL_URL)
             |   |   |   \
             |   |   |    +--> [inference-model-server :9000]  (query embeddings)
             v   v   v
   [Postgres] [Redis] [opensearch :9200 https] [SeaweedFS S3 :8333]
             ^   ^   ^           ^
             |   |   |           |
          [background: supervisord -> Celery primary/light/heavy/docfetching/
           docprocessing/user-file/monitoring/scheduled + beat, Slack/Discord bots]
                 |
                 +--> [indexing-model-server :9000]  (document embeddings)
```

- nginx is the only public service and reproduces upstream's routing (`/api` prefix stripped before reaching the API).
- The background service runs upstream's supervisord set of Celery workers and beat: connector syncs, document fetching/processing, permission syncs, pruning and user-file processing.
- Postgres holds users, connectors, credentials (encrypted), chat history; OpenSearch holds chunks with hybrid keyword/vector search; SeaweedFS holds uploaded files; Redis is the Celery broker, cache and session store.
- The upstream `code-interpreter` service is omitted: it needs the host Docker socket, which Railway does not provide.

## Services

### nginx

Public front door built from `services/nginx` (nginx 1.30 + template adapted from upstream `app.conf.template`).

- Source: repo `baranberkay96/onyx-railway`, root directory `/services/nginx` (Dockerfile build)
- Start command: image default
- Pre-deploy command: none
- Healthcheck: `/nginx-health` (timeout 120 s)
- Public domain: yes, target port `80`
- TCP proxy: none
- Volume: none
- Restart policy: ON_FAILURE (max 10 retries); replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `PORT` | `80` | nginx listen port (public domain target). |
| `ONYX_API_HOST` | `${{api-server.RAILWAY_PRIVATE_DOMAIN}}` | API server host (port 8080). |
| `ONYX_WEB_HOST` | `${{web-server.RAILWAY_PRIVATE_DOMAIN}}` | Web server host (port 3000). |
| `NGINX_PROXY_CONNECT_TIMEOUT` | `300` | Upstream connect timeout (s). |
| `NGINX_PROXY_SEND_TIMEOUT` | `300` | Upstream send timeout (s). |
| `NGINX_PROXY_READ_TIMEOUT` | `300` | Upstream read timeout (s); raise for very long agent runs. |

### api-server

Onyx backend API. Start command matches upstream (`alembic upgrade head` then uvicorn) but binds `::`.

- Source: image `onyxdotapp/onyx-backend:v4.9.0`
- Start command: `/bin/sh -c "alembic upgrade head && exec uvicorn onyx.main:app --host :: --port 8080"`
- Pre-deploy command: none
- Healthcheck: `/health` (timeout 900 s)
- Public domain: no (listens on `8080` privately)
- TCP proxy: none
- Volume: none
- Restart policy: ON_FAILURE (max 10 retries); replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8080` | API port (private; nginx routes /api here). |
| `USER_AUTH_SECRET` | `${{secret(64, "abcdef0123456789")}}` | Signs password-reset, verification, OAuth-state and captcha tokens. Required by the API server. |
| `ENCRYPTION_KEY_SECRET` | `${{secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Encrypts connector credentials and API keys stored in Postgres. Never change after first use. |
| `WEB_DOMAIN` | `https://${{nginx.RAILWAY_PUBLIC_DOMAIN}}` | Public URL (nginx); used for redirects, emails and SSO callbacks. |
| `POSTGRES_HOST` | `${{Postgres.PGHOST}}` | Postgres host (private network). |
| `POSTGRES_PORT` | `${{Postgres.PGPORT}}` | Postgres port. |
| `POSTGRES_USER` | `${{Postgres.POSTGRES_USER}}` | Postgres user. |
| `POSTGRES_PASSWORD` | `${{Postgres.POSTGRES_PASSWORD}}` | Postgres password. |
| `POSTGRES_DB` | `${{Postgres.POSTGRES_DB}}` | Postgres database. |
| `REDIS_HOST` | `${{Redis.REDISHOST}}` | Redis host (Celery broker, cache, login sessions). |
| `REDIS_PORT` | `${{Redis.REDISPORT}}` | Redis port. |
| `REDIS_PASSWORD` | `${{Redis.REDIS_PASSWORD}}` | Redis password. |
| `OPENSEARCH_HOST` | `${{opensearch.RAILWAY_PRIVATE_DOMAIN}}` | OpenSearch host (document index, port 9200, HTTPS with the image's self-signed demo certificate). |
| `OPENSEARCH_ADMIN_PASSWORD` | `${{opensearch.OPENSEARCH_INITIAL_ADMIN_PASSWORD}}` | OpenSearch admin password (reference). |
| `MODEL_SERVER_HOST` | `${{inference-model-server.RAILWAY_PRIVATE_DOMAIN}}` | Inference model server (query embeddings, reranking). |
| `FILE_STORE_BACKEND` | `s3` | Uploaded files and connector blobs go to S3-compatible storage (SeaweedFS). |
| `S3_ENDPOINT_URL` | `http://${{SeaweedFS.RAILWAY_PRIVATE_DOMAIN}}:8333` | SeaweedFS S3 endpoint (private network). Onyx uses path-style addressing. |
| `S3_AWS_ACCESS_KEY_ID` | `${{SeaweedFS.AWS_ACCESS_KEY_ID}}` | SeaweedFS S3 access key. |
| `S3_AWS_SECRET_ACCESS_KEY` | `${{SeaweedFS.AWS_SECRET_ACCESS_KEY}}` | SeaweedFS S3 secret key. |
| `S3_FILE_STORE_BUCKET_NAME` | `onyx-file-store-bucket` | Bucket created by Onyx on first start. |
| `AWS_REGION_NAME` | `us-east-1` | Region sent to the S3 client; us-east-1 avoids a LocationConstraint when Onyx creates the bucket. |
| `ENABLE_PAID_ENTERPRISE_EDITION_FEATURES` | `false` | Enterprise features need an Onyx license. |
| `LOG_LEVEL` | `info` | Log level for API, Celery workers and bots. |
| `VALID_EMAIL_DOMAINS` | `` | Optional. Comma-separated email domains allowed to sign up (e.g. example.com). Empty = anyone with the URL can register. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `60` | Let streaming chat responses finish during redeploys. |

### background

Same backend image running upstream's supervisord set: Celery primary, light, heavy, docfetching, docprocessing, user-file processing, monitoring, scheduled tasks, beat and the Slack/Discord bots. No HTTP listener.

- Source: image `onyxdotapp/onyx-backend:v4.9.0`
- Start command: `/app/scripts/supervisord_entrypoint.sh`
- Pre-deploy command: none
- Healthcheck: none (no HTTP listener / not applicable)
- Public domain: no
- TCP proxy: none
- Volume: none
- Restart policy: ON_FAILURE (max 10 retries); replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `USER_AUTH_SECRET` | `${{api-server.USER_AUTH_SECRET}}` | Must match api-server. |
| `ENCRYPTION_KEY_SECRET` | `${{api-server.ENCRYPTION_KEY_SECRET}}` | Must match api-server. |
| `WEB_DOMAIN` | `https://${{nginx.RAILWAY_PUBLIC_DOMAIN}}` | Public URL (nginx); used for redirects, emails and SSO callbacks. |
| `POSTGRES_HOST` | `${{Postgres.PGHOST}}` | Postgres host (private network). |
| `POSTGRES_PORT` | `${{Postgres.PGPORT}}` | Postgres port. |
| `POSTGRES_USER` | `${{Postgres.POSTGRES_USER}}` | Postgres user. |
| `POSTGRES_PASSWORD` | `${{Postgres.POSTGRES_PASSWORD}}` | Postgres password. |
| `POSTGRES_DB` | `${{Postgres.POSTGRES_DB}}` | Postgres database. |
| `REDIS_HOST` | `${{Redis.REDISHOST}}` | Redis host (Celery broker, cache, login sessions). |
| `REDIS_PORT` | `${{Redis.REDISPORT}}` | Redis port. |
| `REDIS_PASSWORD` | `${{Redis.REDIS_PASSWORD}}` | Redis password. |
| `OPENSEARCH_HOST` | `${{opensearch.RAILWAY_PRIVATE_DOMAIN}}` | OpenSearch host (document index, port 9200, HTTPS with the image's self-signed demo certificate). |
| `OPENSEARCH_ADMIN_PASSWORD` | `${{opensearch.OPENSEARCH_INITIAL_ADMIN_PASSWORD}}` | OpenSearch admin password (reference). |
| `MODEL_SERVER_HOST` | `${{inference-model-server.RAILWAY_PRIVATE_DOMAIN}}` | Inference model server (query embeddings, reranking). |
| `FILE_STORE_BACKEND` | `s3` | Uploaded files and connector blobs go to S3-compatible storage (SeaweedFS). |
| `S3_ENDPOINT_URL` | `http://${{SeaweedFS.RAILWAY_PRIVATE_DOMAIN}}:8333` | SeaweedFS S3 endpoint (private network). Onyx uses path-style addressing. |
| `S3_AWS_ACCESS_KEY_ID` | `${{SeaweedFS.AWS_ACCESS_KEY_ID}}` | SeaweedFS S3 access key. |
| `S3_AWS_SECRET_ACCESS_KEY` | `${{SeaweedFS.AWS_SECRET_ACCESS_KEY}}` | SeaweedFS S3 secret key. |
| `S3_FILE_STORE_BUCKET_NAME` | `onyx-file-store-bucket` | Bucket created by Onyx on first start. |
| `AWS_REGION_NAME` | `us-east-1` | Region sent to the S3 client; us-east-1 avoids a LocationConstraint when Onyx creates the bucket. |
| `ENABLE_PAID_ENTERPRISE_EDITION_FEATURES` | `false` | Enterprise features need an Onyx license. |
| `LOG_LEVEL` | `info` | Log level for API, Celery workers and bots. |
| `INDEXING_MODEL_SERVER_HOST` | `${{indexing-model-server.RAILWAY_PRIVATE_DOMAIN}}` | Indexing model server (document embeddings). |
| `API_SERVER_PROTOCOL` | `http` | Protocol for internal calls to the API (Discord bot). |
| `API_SERVER_HOST` | `${{api-server.RAILWAY_PRIVATE_DOMAIN}}` | API server host for internal calls. |
| `DISCORD_BOT_TOKEN` | `` | Optional. Enables the Discord bot. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `120` | Give Celery workers time to finish tasks during redeploys. |

### web-server

Next.js UI. Healthcheck uses a static asset because `/` redirects (Railway healthchecks need HTTP 200).

- Source: image `onyxdotapp/onyx-web-server:v4.9.0`
- Start command: image default
- Pre-deploy command: none
- Healthcheck: `/logo.png` (timeout 300 s)
- Public domain: no (listens on `3000` privately)
- TCP proxy: none
- Volume: none
- Restart policy: ON_FAILURE (max 10 retries); replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `PORT` | `3000` | Next.js port (private; nginx routes / here). |
| `HOSTNAME` | `::` | Bind address; :: accepts IPv4 and IPv6 from nginx. |
| `INTERNAL_URL` | `http://${{api-server.RAILWAY_PRIVATE_DOMAIN}}:8080` | API URL used for server-side rendering. |
| `WEB_DOMAIN` | `https://${{nginx.RAILWAY_PUBLIC_DOMAIN}}` | Public URL. |

### inference-model-server

Serves query embeddings and reranking. Image is near-distroless (no shell), so the start command calls uvicorn directly to bind `::`.

- Source: image `onyxdotapp/onyx-model-server:v4.9.0`
- Start command: `python -m uvicorn model_server.main:app --host :: --port 9000`
- Pre-deploy command: none
- Healthcheck: `/api/health` (timeout 900 s)
- Public domain: no (listens on `9000` privately)
- TCP proxy: none
- Volume: none
- Restart policy: ON_FAILURE (max 10 retries); replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `PORT` | `9000` | Model server port (Railway healthcheck). |
| `LOG_LEVEL` | `info` | Log level. |

### indexing-model-server

Same image with `INDEXING_ONLY=True`; used by background workers for document embeddings.

- Source: image `onyxdotapp/onyx-model-server:v4.9.0`
- Start command: `python -m uvicorn model_server.main:app --host :: --port 9000`
- Pre-deploy command: none
- Healthcheck: `/api/health` (timeout 900 s)
- Public domain: no (listens on `9000` privately)
- TCP proxy: none
- Volume: none
- Restart policy: ON_FAILURE (max 10 retries); replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `PORT` | `9000` | Model server port (Railway healthcheck). |
| `INDEXING_ONLY` | `True` | Indexing mode: serves document embedding requests from the background workers. |
| `LOG_LEVEL` | `info` | Log level. |

### opensearch

Built from `services/opensearch`. Document index with the security plugin's demo TLS (Onyx defaults to HTTPS without certificate verification). No HTTP healthcheck because the API requires TLS + auth.

- Source: repo `baranberkay96/onyx-railway`, root directory `/services/opensearch` (Dockerfile build)
- Start command: image default
- Pre-deploy command: none
- Healthcheck: none (no HTTP listener / not applicable)
- Public domain: no
- TCP proxy: none
- Volume: `/usr/share/opensearch/data`
- Restart policy: ON_FAILURE (max 10 retries); replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `discovery.type` | `single-node` | Single-node cluster (as upstream). |
| `OPENSEARCH_INITIAL_ADMIN_PASSWORD` | `Os1-${{secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Admin password for the security plugin (prefix guarantees upper/lower/digit/special). |
| `OPENSEARCH_JAVA_OPTS` | `-Xms2g -Xmx2g` | JVM heap (upstream value). Keep about half of the RAM OpenSearch may use. |
| `bootstrap.memory_lock` | `false` | memlock ulimits cannot be raised on Railway. |
| `node.store.allow_mmap` | `false` | Do not depend on the host's vm.max_map_count, which containers cannot change. |
| `network.host` | `::` | Listen on IPv6 and IPv4 for private-network clients. |
| `DISABLE_PERFORMANCE_ANALYZER_AGENT_CLI` | `true` | Do not start the Performance Analyzer side JVM (saves ~0.3 GB). |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `60` | Allow a clean shutdown on redeploy. |

### Postgres

Railway base Postgres (`_railway-base/postgres.json`) with the start command extended by `-c max_connections=250` (upstream value).

- Source: image `ghcr.io/railwayapp-templates/postgres-ssl:18`
- Start command: `/usr/bin/tini -g -- /usr/local/bin/wrapper.sh postgres -p 5432 -c listen_addresses=* -c max_connections=250`
- Pre-deploy command: none
- Healthcheck: none (no HTTP listener / not applicable)
- Public domain: no
- TCP proxy: none
- Volume: `/var/lib/postgresql/data`
- Restart policy: ON_FAILURE (max 10 retries); replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `PGDATA` | `/var/lib/postgresql/data/pgdata` | Location where the database will be initialized |
| `PGHOST` | `${{RAILWAY_PRIVATE_DOMAIN}}` | Railway Private Domain Name. |
| `PGPORT` | `5432` | Port to connect to Postgres. |
| `PGUSER` | `${{ POSTGRES_USER }}` | Required variable for Data panel |
| `PGDATABASE` | `${{POSTGRES_DB}}` | Required variable for the data panel. |
| `PGPASSWORD` | `${{POSTGRES_PASSWORD}}` | Required variable for Data panel |
| `POSTGRES_DB` | `railway` | Default database created when image is started. |
| `DATABASE_URL` | `postgresql://${{PGUSER}}:${{POSTGRES_PASSWORD}}@${{RAILWAY_PRIVATE_DOMAIN}}:5432/${{PGDATABASE}}` | URL to connect to Postgres database. |
| `POSTGRES_USER` | `postgres` | User to connect to Postgres DB |
| `SSL_CERT_DAYS` | `820` | SSL certificate expiry in days. |
| `POSTGRES_PASSWORD` | `${{ secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") }}` | Password to connect to DB |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `60` | Allow Postgres to cleanly shut down |

### Redis

Railway base Redis (`_railway-base/redis.json`, verbatim).

- Source: image `redis:8.2`
- Start command: `/bin/sh -c "rm -rf $RAILWAY_VOLUME_MOUNT_PATH/lost+found/ && exec docker-entrypoint.sh redis-server --requirepass $REDIS_PASSWORD --save 60 1 --dir $RAILWAY_VOLUME_MOUNT_PATH"`
- Pre-deploy command: none
- Healthcheck: none (no HTTP listener / not applicable)
- Public domain: no
- TCP proxy: none
- Volume: `/data`
- Restart policy: ON_FAILURE (max 10 retries); replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `REDISHOST` | `${{RAILWAY_PRIVATE_DOMAIN}}` | Private network hostname of the Redis service, only resolvable from services in the same environment |
| `REDISPORT` | `6379` | Port that Redis listens on |
| `REDISUSER` | `default` | Username for authenticating with Redis |
| `REDIS_URL` | `redis://${{ REDISUSER }}:${{ REDIS_PASSWORD }}@${{ REDISHOST }}:${{ REDISPORT }}` | Connection string for connecting to Redis using the private network |
| `REDISPASSWORD` | `${{REDIS_PASSWORD}}` | Alias of REDIS_PASSWORD for clients that expect the unseparated name |
| `REDIS_PASSWORD` | `${{ secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") }}` | Randomly generated password for authenticating with Redis |

### SeaweedFS

S3 gateway + master + volume + filer in one process (`weed server -s3`), data on the volume. Admin credentials come from `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`. Replaces upstream MinIO.

- Source: image `chrislusf/seaweedfs:4.48`
- Start command: `/entrypoint.sh server -ip=127.0.0.1 -ip.bind=:: -s3 -s3.port=8333`
- Pre-deploy command: none
- Healthcheck: `/healthz` (timeout 120 s)
- Public domain: no (listens on `8333` privately)
- TCP proxy: none
- Volume: `/data`
- Restart policy: ON_FAILURE (max 10 retries); replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | `${{secret(20, "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Admin access key for the S3 gateway (SeaweedFS reads it from the environment). |
| `AWS_SECRET_ACCESS_KEY` | `${{secret(40, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Admin secret key for the S3 gateway. |
| `PORT` | `8333` | S3 gateway port; Railway healthcheck uses /healthz. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `30` | Allow a clean shutdown on redeploy. |

## Improvements over market templates

1. **Onyx v4.9.0** (current release) with images pinned; OpenSearch kept at the version Onyx pins (3.6.0).
2. **No MinIO.** The base used `onyxdotapp/minio` (an archived MinIO mirror). Replaced by SeaweedFS's S3 gateway with generated credentials and a volume, because Onyx forces path-style S3 requests that Railway Buckets reject.
3. **IPv6-safe private networking:** api-server (`uvicorn --host ::`), web-server (`HOSTNAME=::`), both model servers (`uvicorn ... --host ::`, overriding the image's hardcoded `0.0.0.0`), OpenSearch (`network.host=::`) and nginx (`listen [::]`) accept IPv4 and IPv6, so the stack works in legacy IPv6-only Railway environments too.
4. **nginx as a real image** (`services/nginx`) adapted from upstream's `app.conf.template`: resolves `*.railway.internal` at request time (no crash or reload loop while backends start), forwards Railway's `X-Forwarded-Proto` so Onyx builds `https` URLs, keeps upstream timeouts and 5 GB uploads.
5. **Postgres `max_connections=250`** as upstream requires, set explicitly on the Railway base Postgres (its wrapper only raises the limit from the second boot).
6. **Persistent Redis** (Railway base) so login sessions survive Redis restarts; upstream runs Redis without persistence.
7. **OpenSearch tuned for containers:** start script fixes volume ownership and drops to uid 1000 without `RAILWAY_RUN_UID` tricks, `allow_mmap=false`, `memory_lock=false`, performance-analyzer side JVM disabled, generated admin password that always satisfies the password policy.
8. **Model servers without root:** embeddings are baked into the image, so the HuggingFace cache volumes (which forced the market template to run as root) are dropped.
9. **Healthchecks** on nginx, api-server, web-server, both model servers and SeaweedFS, with long timeouts for first-boot migrations.

## Resource estimate

Onyx is the heaviest app in this batch. Upstream's resource overlay allows up to 10 GB for `background`, 4 GB for the API and 5 GB per model server.

| Service | Idle RAM | Typical RAM | Typical vCPU | Volume |
|---|---|---|---|---|
| nginx | 0.02 GB | 0.05 GB | 0.05 | – |
| api-server | 0.8 GB | 1.5 GB | 0.5 | – |
| background (Celery workers + beat) | 2.0 GB | 3.5 GB | 1.0 | – |
| web-server | 0.2 GB | 0.4 GB | 0.1 | – |
| inference-model-server | 1.2 GB | 2.0 GB | 0.5 | – |
| indexing-model-server | 1.2 GB | 2.5 GB | 1.0 (while indexing) | – |
| opensearch (2 GB heap) | 2.6 GB | 3.2 GB | 0.4 | 5–20 GB |
| Postgres | 0.15 GB | 0.4 GB | 0.1 | 1–3 GB |
| Redis | 0.05 GB | 0.2 GB | 0.05 | < 0.5 GB |
| SeaweedFS | 0.1 GB | 0.25 GB | 0.05 | 1–20 GB |
| **Total** | **~8.3 GB** | **~13.9 GB** | **~3.8** | **~8–45 GB** |

Railway prices: RAM $10/GB-month, vCPU $20/vCPU-month, volume $0.15/GB-month.

- **Idle:** 8.3 GB × $10 + ~0.5 vCPU × $20 + 9 GB × $0.15 ≈ **$94/month**.
- **Typical (a team with several connectors syncing daily):** 13.9 GB × $10 + 3.8 vCPU × $20 + 30 GB × $0.15 ≈ **$220/month**. Initial indexing of large sources temporarily raises background and indexing-model-server CPU. LLM costs are billed by your provider.

**Minimum plan: Hobby** (several services exceed Trial's 1 GB). Pro is recommended for production (per-service headroom, volumes above 5 GB for OpenSearch and SeaweedFS).

## Verification checklist

1. All services deploy green: `nginx` `/nginx-health`, `api-server` `/health` (first boot runs Alembic migrations; allow up to 15 minutes), `web-server` `/logo.png`, both model servers `/api/health`, SeaweedFS `/healthz`.
2. Open the public URL, create the first account (it becomes the admin), and configure an LLM provider in the admin panel.
3. Upload a file in a chat or project; SeaweedFS logs show the `onyx-file-store-bucket` bucket being created and written.
4. Add a connector (for example a Web or File connector), let it index, and ask a question that cites the indexed documents (proves background → indexing-model-server → OpenSearch → api-server).
5. Check background logs for Celery beat scheduling and successful docfetching/docprocessing tasks.
6. Redeploy Postgres, Redis, OpenSearch and SeaweedFS; users, connectors, indexed documents and uploaded files persist, and you stay logged in.
7. Scale `indexing-model-server` or give `background` more resources and re-index a large source.

## Open questions

- **Railway Bucket support:** possible only if Onyx stops forcing path-style for custom endpoints (or via `AWS_ENDPOINT_URL_S3` without `S3_ENDPOINT_URL`, which would also redirect Onyx's AWS S3 connector). Not used.
- **Postgres 18 / Redis 8.2 vs upstream 15.2 / 7.4:** newer than the versions Onyx ships in compose; not verified against Onyx CI.
- **`allow_mmap=false` on OpenSearch** trades some search speed for independence from the host's `vm.max_map_count`; remove it if the host allows mmap and you index large corpora.
- **Model downloads:** the default embedding model is baked into the image. If you switch to another self-hosted embedding or reranking model, it is downloaded on every model-server restart (no cache volume). Add a volume at `/app/.cache/huggingface` with `RAILWAY_RUN_UID=0` if that matters.
- **Code interpreter tool** is not available (needs Docker socket).
- **Background is one container** (upstream docker layout); very large deployments may want Onyx's Kubernetes split per Celery worker.
- Not deploy-tested in this package (local files only).

## Deploy test findings (2026-10-11)

Not yet deploy-tested, but api-server and both model servers used single-worker uvicorn on `::`, which is IPv6-only (asyncio sets IPV6_V6ONLY); this failed Dify's agent backend healthcheck. Fix applied pre-emptively: `--host 0.0.0.0`.
