# Deployment Requirements: Azure Container Apps

This document outlines the requirements and strategy for deploying the `medata` application to Azure Container Apps (ACA), running in parallel with the existing Vercel deployment.

## 1. Objective
Deploy the SvelteKit-based `medata` application to Azure Container Apps to enable a scalable, containerized production environment while retaining the ability to deploy to Vercel for development/preview.

## 2. Containerization Strategy

### 2.1 Dynamic Adapter Configuration
To support both Vercel and Docker (Node.js) environments, `svelte.config.js` must dynamically select the adapter based on an environment variable (e.g., `ADAPTER_PROVIDER`).

- **Default**: `@sveltejs/adapter-vercel`
- **Docker**: `@sveltejs/adapter-node`

**Action**: Modify `svelte.config.js` to conditional import the adapter.

### 2.2 Dockerfile
*Assumed to be handled by `dev-docker` branch.*
- Base Image: Node 22 (matching `runtime: "nodejs22.x"` in current config).
- Port: Expose port 3000 (default for adapter-node) or configurable via `PORT` env var.
- Environment: Ensure `BODY_SIZE_LIMIT` and other node-specific configs are tuned.

## 3. Infrastructure (Azure)

Follow the pattern from `sanarte` repository using `az containerapp update` with a YAML configuration.

### 3.1 Resources
- **Resource Group**: `rg-medata-prod` (suggested)
- **Container Registry**: GitHub Container Registry (GHCR) `ghcr.io/troobit/medata`
- **Container Apps Environment**: `cappenv-medata-prod`
- **Managed Identity**: User-assigned managed identity for GitHub Actions OIDC federation.

### 3.2 Redis / KV Store
The application uses `@vercel/kv`.
- **Option A (Minimal Change)**: Continue using Vercel KV via HTTP. Inject `KV_REST_API_URL` and `KV_REST_API_TOKEN` as secrets in the Azure Container App.
- **Option B (Azure Native)**: Migration to Azure Cache for Redis. Requires switching from `@vercel/kv` to `ioredis` or ensuring compatible connection strings. *Recommendation: Stick to Option A initially for minimal code changes.*

## 4. CI/CD Pipelines (GitHub Actions)

Create workflows mirroring `sanarte` repository.

### 4.1 Build Workflow (`.github/workflows/build-container.yml`)
- Trigger: `workflow_dispatch` and/or push to `main` (optional).
- Steps:
  1. Checkout code.
  2. Set up Docker Buildx.
  3. Login to GHCR.
  4. Extract metadata (tags, labels).
  5. Build and Push to `ghcr.io/troobit/medata`.

### 4.2 Deploy Workflow (`.github/workflows/deploy-container-app.yml`)
- Trigger: `workflow_dispatch`.
- Inputs: `image` (tag), `rg_name`, `app_name`.
- Steps:
  1. Checkout.
  2. Substitute image tag in local config file.
  3. Azure Login (OIDC).
  4. `az containerapp update` using the config file.

## 5. Configuration Management

### 5.1 ACA Configuration File
Create `config/medata-ca.yaml` to define the container app spec.
- **Ingress**: External, Target Port 3000 (match Dockerfile).
- **Scale**: Min 0 (serverless), Max 5.
- **Env Vars**:
  - `KV_REST_API_URL`: Secret reference.
  - `KV_REST_API_TOKEN`: Secret reference.
  - `ORIGIN`: Production URL.
  - `BODY_SIZE_LIMIT`: If applicable.

### 5.2 Secrets
Secrets to be stored in Azure Container App or Key Vault:
- `kv-rest-api-url`
- `kv-rest-api-token`
- `cr-password` (for GHCR pull access)

## 6. Implementation Checklist
- [ ] Install `@sveltejs/adapter-node` as a dev dependency.
- [ ] Update `svelte.config.js` for dynamic adapter selection.
- [ ] Create `config/medata-ca.yaml` template.
- [ ] Create `.github/workflows/build-container.yml`.
- [ ] Create `.github/workflows/deploy-container-app.yml`.
- [ ] Verify `dev-docker` branch produces a compatible image.