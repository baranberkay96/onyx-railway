# Deploy and Host Onyx with Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/onyx-v4-enterprise-ai-search)

Onyx is an open-source AI platform for enterprise search and chat: it connects to tools like Slack, Google Drive, Confluence, Jira and GitHub, indexes their content and answers questions with citations using the LLM of your choice. This community template deploys the full Onyx v4 stack on Railway, including connectors, document indexing and local embedding models.

## About Hosting Onyx

A complete Onyx deployment has many moving parts. An API server and a Next.js web app sit behind nginx; a background service runs Celery workers that pull documents from connectors, split and embed them, sync permissions and keep the index fresh. Two model servers run the embedding models locally, OpenSearch stores the hybrid keyword and vector index, Postgres keeps users, connectors and chat history, Redis brokers the task queues and holds sessions, and an S3-compatible store keeps uploaded files. This template wires all of it together over Railway's private network with generated secrets, persistent volumes and healthchecks. It is resource-intensive: plan for roughly 8–14 GB of RAM.

## Common Use Cases

- Ask natural-language questions across company knowledge in Slack, Google Drive, Confluence, Notion, Jira, GitHub and other sources, with cited answers.
- Give teams a private ChatGPT-style assistant that can use internal documents, web search and custom agents.
- Build agents and assistants scoped to document sets for support, sales enablement or engineering.
- Keep indexed company data and chat history on infrastructure you control.

## Dependencies for Onyx Hosting

- Onyx images `onyxdotapp/onyx-backend`, `onyx-web-server` and `onyx-model-server`, version v4.9.0
- OpenSearch 3.6.0 (document index)
- PostgreSQL (Railway Postgres 18) and Redis (Railway Redis 8.2)
- S3-compatible storage (SeaweedFS 4.48)
- nginx 1.30 as the front door
- An LLM provider (OpenAI, Anthropic, Azure, Bedrock, Ollama, a LiteLLM gateway, ...), configured in the admin panel

### Deployment Dependencies

- Onyx documentation: https://docs.onyx.app
- Docker Compose deployment: https://github.com/onyx-dot-app/onyx/tree/v4.9.0/deployment/docker_compose
- Environment reference: https://github.com/onyx-dot-app/onyx/blob/v4.9.0/deployment/docker_compose/env.template
- Connectors overview: https://docs.onyx.app/admins/connectors/overview
- SeaweedFS S3 API: https://github.com/seaweedfs/seaweedfs/wiki/Amazon-S3-API

### Implementation Details

| Service | Role | Public | Storage |
|---|---|---|---|
| nginx | Routes `/api` to the API and the rest to the web app | Yes (port 80) | – |
| api-server | REST/streaming API, runs migrations | No | – |
| background | Celery workers + beat (connectors, indexing, pruning, permission sync) | No | – |
| web-server | Next.js UI | No | – |
| inference-model-server | Query embeddings, reranking | No | – |
| indexing-model-server | Document embeddings | No | – |
| opensearch | Hybrid search index | No | Volume |
| Postgres | Users, connectors, chat history | No | Volume |
| Redis | Task broker, cache, sessions | No | Volume |
| SeaweedFS | S3 file store for uploads | No | Volume |

**First login**

1. Wait for `api-server` to become healthy (the first start runs database migrations and can take up to 15 minutes).
2. Open the nginx public URL and create your account. The first account becomes the administrator.
3. In the admin panel, add an LLM provider, then add connectors (Web, Slack, Google Drive, Confluence, ...) and let them index.
4. To restrict sign-ups, set `VALID_EMAIL_DOMAINS` on `api-server` or configure SSO under Admin Panel > Organization > SSO Providers.

**Scaling:** indexing throughput depends on `background` and `indexing-model-server` CPU/RAM; give them more resources for large sources. Search and chat load scales with `api-server` and `inference-model-server`. OpenSearch scales vertically (raise `OPENSEARCH_JAVA_OPTS` together with available RAM).

**Pinning and upgrades:** all Onyx services use the same tag (`v4.9.0`); upgrade `api-server`, `background`, `web-server` and both model servers together and read the release notes first. Migrations run automatically when `api-server` starts. OpenSearch is pinned in `services/opensearch/Dockerfile` to the version Onyx's compose file uses.

**File storage:** uploads use SeaweedFS because Onyx's S3 client requires path-style requests. If you prefer fewer services, set `FILE_STORE_BACKEND=postgres` on `api-server` and `background` before first use and remove SeaweedFS.

### Why Deploy Onyx on Railway?

Railway runs Onyx's ten services as one project with private networking, persistent volumes, generated credentials and usage-based billing, so you get the full connector-and-indexing stack without operating Kubernetes. Resources can be raised per service as your indexed content grows.
