# MeData

A personal data tracking application for logging meal macros, insulin doses, and BSL. Uses ML-powered food recognition to estimate macros from photos.

## Getting Started

```bash
npm install
npm run dev
```

The app runs at `http://localhost:5173` by default.

## Data Storage

MeData uses **IndexedDB** for client-side data storage via [Dexie.js](https://dexie.org/). No database setup or server is required - the database is automatically created in your browser when you first use the app.

### Troubleshooting: "The user denied permission to access the database"

This error occurs when the browser cannot access IndexedDB. Common causes and solutions:

| Cause                          | Solution                                                                        |
| ------------------------------ | ------------------------------------------------------------------------------- |
| **Private/Incognito mode**     | Use a regular browser window. Some browsers restrict IndexedDB in private mode. |
| **Storage permissions denied** | Check browser settings and allow storage for `localhost`                        |
| **Accessing via `file://`**    | Always run via `npm run dev` and access at `http://localhost:5173`              |
| **Browser storage disabled**   | Enable cookies/site data in browser settings                                    |
| **Low disk space**             | Free up disk space on your device                                               |

To reset storage permissions in Chrome: Settings → Privacy and security → Site settings → View permissions and data stored across sites → Search for "localhost" → Reset permissions.
