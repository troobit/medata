# MeData

A personal data tracking application for logging meal macros, insulin doses, and BSL. Uses ML-powered food recognition to estimate macros from photos.

## Getting Started

```bash
npm install
npm run dev
```

## Storage

MeData stores all data locally in your browser using IndexedDB. No server or cloud account is required.

### Troubleshooting

**"Permission denied" or "Database access blocked" errors:**

This typically occurs when:

1. **Safari Private Browsing**: IndexedDB is disabled in private/incognito mode on Safari. Use a regular browsing window instead.
2. **Blocked site data**: Some browsers allow users to block all site data. Check your browser's privacy settings:
   - Safari: Settings → Privacy → uncheck "Prevent cross-site tracking" or add MeData to allowed sites
   - Chrome: Settings → Privacy and security → Site settings → ensure the site can store data
   - Firefox: Settings → Privacy & Security → ensure "Standard" or allow site data for MeData
3. **Storage quota exceeded**: If your device storage is full, the browser may refuse to create new databases. Free up space and try again.

**Data not persisting between sessions:**

- Ensure you're not in private/incognito mode
- Some browsers clear IndexedDB data when "Clear browsing data" includes site data
- iOS Safari may clear IndexedDB if the device runs low on storage (use "Add to Home Screen" for better data persistence)

**No manual database setup required**: The app automatically creates and manages its database on first load.
