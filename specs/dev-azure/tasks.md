---
references:
    - requirements.md
---
# Azure Container Apps Deployment

## R1: Dynamic Adapter Configuration

- [x] 1. Investigate: Review current svelte.config.js adapter setup

- [x] 2. Implement: Install @sveltejs/adapter-node as dev dependency

- [x] 3. Implement: Modify svelte.config.js for ADAPTER_PROVIDER env-based selection

- [x] 4. Verify: Test build with both adapter-vercel and adapter-node

## R2: ACA Configuration File

- [ ] 5. Investigate: Review sanarte repo ACA config pattern

- [ ] 6. Implement: Create config/medata-ca.yaml with ingress, scaling, and env vars

- [ ] 7. Implement: Define secrets placeholders for KV_REST_API_URL, KV_REST_API_TOKEN, cr-password

- [ ] 8. Verify: Validate YAML structure against az containerapp schema

## R3: Build Container Workflow

- [ ] 9. Investigate: Review sanarte build-container workflow

- [ ] 10. Implement: Create .github/workflows/build-container.yml with Buildx, GHCR login, metadata extraction

- [ ] 11. Implement: Configure workflow_dispatch trigger

- [ ] 12. Verify: Test workflow manually via workflow_dispatch

## R4: Deploy Container App Workflow

- [ ] 13. Investigate: Review sanarte deploy-container-app workflow

- [ ] 14. Implement: Create .github/workflows/deploy-container-app.yml with OIDC Azure login

- [ ] 15. Implement: Add workflow_dispatch inputs for image tag, rg_name, app_name

- [ ] 16. Implement: Add step to substitute image tag in config file before az containerapp update

- [ ] 17. Verify: Test deploy workflow against Azure environment

- [ ] 18. Implement: Create .github/workflows/destroy-container-app.yml with OIDC Azure login

- [ ] 19. Implement: Add workflow_dispatch inputs for image tag, rg_name, app_name

- [ ] 20. Implement: Add step to substitute image tag in config file before az containerapp update

- [ ] 21. Verify: Test deploy workflow against Azure environment

- [ ] 22. Verify: after running the pipeline, no Azure resources should remain

## R5: Destroy Container App Workflow


## R5: Integration Verification

- [ ] 23. Investigate: Verify dev-docker branch Dockerfile compatibility

- [ ] 24. Implement: End-to-end test: build image, push to GHCR, deploy to ACA

- [ ] 25. Verify: Confirm application runs correctly on ACA with Vercel KV connectivity

## R5: Documentation

- [ ] 26. Clearly document changes made - and how to run builds for both original and new deployment set up as currently configure. Remain brief, and exclude things like contributing or others.
