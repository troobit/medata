# Prerequisites for MeData MVP

These tasks must be completed by the user before or during implementation. They require manual configuration that cannot be performed by an automated coding agent.

---

## Before Starting

- [ ] **AI Provider API Key** - Obtain API key for at least one AI provider
  - Claude API key from Anthropic (recommended)
  - OR OpenAI API key
  - OR Gemini API key
  - Store securely - will be added to environment variables

---

## Before Phase 4 (Meal Storage & History)

- [ ] **Azure Cosmos DB Setup**
  - Create Azure account if not exists
  - Create Cosmos DB account (free tier available)
  - Create database named `medata`
  - Create containers: `meals` (partition key: `/partitionKey`) and `presets` (partition key: `/category`)
  - Copy connection string for environment variables
  - **Blocks tasks:** 30, 47

- [ ] **Azure Blob Storage Setup**
  - Create Storage Account in Azure
  - Create container named `images`
  - Configure lifecycle management policy for 30-day TTL on images
  - Copy connection string for environment variables
  - **Blocks tasks:** 32, 33

- [ ] **Environment Variables Configuration**
  - Copy `.env.example` to `.env.local`
  - Add AI provider API key: `ANTHROPIC_API_KEY` or equivalent
  - Add Cosmos DB connection string: `COSMOS_CONNECTION_STRING`
  - Add Blob Storage connection string: `BLOB_STORAGE_CONNECTION_STRING`
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
