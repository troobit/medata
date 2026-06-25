# Prerequisites for MVP Refinement

These tasks require human intervention and must be completed before or during implementation.

## Before Starting

- [ ] **Recognition backend (choose one):**
  - **Option A — Local Ollama (free, no account):** Install from [ollama.com](https://ollama.com), run `ollama pull llava`, set `RECOGNITION_BASE_URL=http://localhost:11434` and `RECOGNITION_MODEL=llava` in `.env`
  - **Option B — Cloud model:** Obtain API key from your provider, set `RECOGNITION_BASE_URL`, `RECOGNITION_MODEL`, and `RECOGNITION_API_KEY` in `.env`
  - **Option C — Mock mode:** Set `RECOGNITION_MOCK_MODE=true` in `.env` to skip real backend calls during development
  - Note: increase `RECOGNITION_TIMEOUT_MS` (default 10000) if using large local models (Ollama 7B+ may need 30000–60000ms)

- [ ] **Azure Cosmos DB:** Obtain the connection string from the provisioned Cosmos DB resource and add it to `.env` as `AZURE_COSMOS_CONNECTION_STRING=`

- [ ] **Azure Blob Storage:** Obtain the container URL with SAS token from the provisioned Blob Storage resource and add it to `.env` as `AZURE_BLOB_STORAGE_URL=`

## During Implementation

- [ ] **Before testing Task 24 (HTTPS):** Note that after adding `@vitejs/plugin-basic-ssl`, the dev server moves to `https://localhost:5173`. Your browser will show a security warning on first visit — click "Advanced → Proceed" to accept the self-signed certificate.

- [ ] **Before mobile testing (Tasks 19, 23):** Find your machine's LAN IP address (`ifconfig | grep "inet 192"` on Mac) to construct the mobile access URL: `https://192.168.x.x:5173`

## Before Testing

- [ ] **Mobile device:** A physical iOS or Android phone on the same WiFi network as your dev machine is required to validate camera capture (Reqs 2.1, 2.2, 2.4) and LAN access (Req 1.2). These cannot be tested with browser devtools device emulation.
