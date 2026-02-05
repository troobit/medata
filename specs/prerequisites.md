# Prerequisites for MeData MVP

These tasks must be completed by the user before or during implementation. They require manual configuration that cannot be performed by an automated coding agent.

---

## Before Starting

- [x] **AI Provider API Key** - Obtain API key for at least one AI provider *(COMPLETED)*
  - Claude API key from Anthropic (recommended) - configured as `CLAUDE_API_KEY`
  - ~~OR OpenAI API key~~
  - ~~OR Gemini API key~~
  - Stored in `.env.local`

---

## Before Phase 4 (Meal Storage & History)

- [x] **Azure Cosmos DB Setup** *(COMPLETED)*
  - Azure account exists
  - Cosmos DB account configured at `dbmedata.documents.azure.com`
  - Database and containers to be created on first use (or verify exist)
  - Connection string configured as `PRIMARY_CONNECTION_STRING` in `.env.local`
  - **Blocks tasks:** 30, 47

- [x] **Azure Blob Storage Setup** *(COMPLETED)*
  - Storage Account: `medatablobs`
  - Container: `images`
  - SAS token configured as `BLOB_SAS_TOKEN` and `BLOB_SAS_URL` in `.env.local`
  - Note: 30-day TTL lifecycle policy should be configured in Azure portal
  - **Blocks tasks:** 32, 33

- [x] **Environment Variables Configuration** *(COMPLETED - needs renaming)*
  - `.env.local` exists with credentials (rename variables during task 7):
    - `CLAUDE_API_KEY` → `ANTHROPIC_API_KEY`
    - `AZURE_DB_URI`, `PRIMARY_KEY`, `PRIMARY_CONNECTION_STRING` → `AZURE_COSMOS_CONNECTION_STRING`
    - `BLOB_SAS_TOKEN`, `BLOB_SAS_URL` → `AZURE_BLOB_STORAGE_URL`
  - **Blocks tasks:** 16, 30, 32

---

## Before Testing

- [ ] **Test Photo Set**
  - Curate 10-20 food photos for testing
  - Include various foods, lighting conditions, and edge cases
  - Include Australian nutrition labels for label scanning tests
  - Per design §6.2 manual test checklist

---

## Notes

- Azure free tier provides sufficient resources for MVP development and testing
- All credentials must remain server-side only (per Req 11.5)
- Never commit `.env.local` or actual credentials to version control
