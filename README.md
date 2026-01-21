# MeData

A personal data tracking application for logging meal macros, insulin doses, and BSL. Uses ML-powered food recognition to estimate macros from photos.

## Getting Started

### 1. Install Dependencies

```bash
pnpm install
```

### 2. Configure Environment

Copy the example environment file and configure authentication:

```bash
cp .env.example .env.local
```

Edit `.env.local` with the following required variables:

```bash
# WebAuthn Configuration
AUTH_RP_ID=localhost
AUTH_ORIGIN=http://localhost:5173
AUTH_CREDENTIALS_PATH=./data/credentials.json

# Session Security (generate with: openssl rand -base64 32)
AUTH_SESSION_SECRET=your-32-character-minimum-secret-here

# Bootstrap Token for initial enrollment (generate with: openssl rand -hex 16)
AUTH_BOOTSTRAP_TOKEN=your-bootstrap-token-here
```

### 3. Start Development Server

```bash
pnpm dev
```

### 4. Initial Authentication Setup (Bootstrap)

On first run, no credentials exist. You'll need to enroll your first security key:

1. Open `http://localhost:5173` in your browser
2. You'll see a bootstrap enrollment prompt
3. Enter the `AUTH_BOOTSTRAP_TOKEN` value from your `.env.local`
4. Follow the browser prompt to register a security key (hardware key or virtual authenticator)
5. Once enrolled, you're logged in and can access the app

**After initial enrollment**, remove or rotate `AUTH_BOOTSTRAP_TOKEN` to prevent unauthorised credential registration.

## Deploying to Vercel

MeData can be deployed to Vercel with YubiKey authentication. Vercel KV is required for credential storage since serverless functions have a read-only filesystem.

### 1. Set Up Vercel KV

**Via Vercel Dashboard:**

1. Go to your Vercel project → **Storage** tab
2. Click **Create Database** → **KV**
3. Name it (e.g., `medata-auth`)
4. Click **Create** and it will auto-link to your project

**Via CLI:**

```bash
vercel storage add kv medata-auth
```

### 2. Configure Environment Variables

```bash
# Set the production domain
vercel env add AUTH_RP_ID production
# Enter: your-domain.vercel.app

vercel env add AUTH_ORIGIN production
# Enter: https://your-domain.vercel.app

# Generate and set session secret
vercel env add AUTH_SESSION_SECRET production
# Enter: $(openssl rand -base64 32)

# Generate bootstrap token for initial enrollment
vercel env add AUTH_BOOTSTRAP_TOKEN production
# Enter: $(openssl rand -hex 16)
```

Note: `KV_REST_API_URL` and `KV_REST_API_TOKEN` are automatically set when you link the KV store.

### 3. Deploy

```bash
vercel --prod
```

### 4. Enroll Your YubiKey

1. Visit `https://your-domain.vercel.app`
2. Enter your bootstrap token when prompted
3. Insert and tap your YubiKey
4. You're now authenticated

### 5. Remove Bootstrap Token (Important)

After successful enrollment:

```bash
vercel env rm AUTH_BOOTSTRAP_TOKEN production
vercel --prod  # Redeploy to apply
```

### Environment Variables for Production

| Variable               | Required     | Description                                   |
| ---------------------- | ------------ | --------------------------------------------- |
| `AUTH_RP_ID`           | Yes          | Your Vercel domain (e.g., `myapp.vercel.app`) |
| `AUTH_ORIGIN`          | Yes          | Full URL with `https://`                      |
| `AUTH_SESSION_SECRET`  | Yes          | 32+ char secret for session signing           |
| `AUTH_BOOTSTRAP_TOKEN` | First deploy | Remove after initial enrollment               |
| `KV_REST_API_URL`      | Auto         | Set automatically when KV is linked           |
| `KV_REST_API_TOKEN`    | Auto         | Set automatically when KV is linked           |

### Troubleshooting Vercel Deployment

| Problem                         | Solution                                                       |
| ------------------------------- | -------------------------------------------------------------- |
| `ENOENT: mkdir './data'`        | KV is not linked. Add a KV store in Vercel dashboard.          |
| `Invalid origin`                | Ensure `AUTH_ORIGIN` matches your actual URL exactly           |
| YubiKey not working             | Verify the domain uses HTTPS (required for WebAuthn)           |
| Credentials lost after redeploy | This shouldn't happen with KV. Verify KV is linked.            |
| Bootstrap not prompting         | Credentials already exist in KV. Check Vercel KV data browser. |

See [docs/auth.md](docs/auth.md) for detailed KV configuration and troubleshooting.

## Authentication

MeData uses WebAuthn (FIDO2) passkey authentication - no passwords required. This provides phishing-resistant, cryptographic authentication.

### How It Works

- **Single-user model**: The app is designed for personal use by one owner
- **Passkey authentication**: Uses hardware security keys (YubiKey, etc.) or platform authenticators (Touch ID, Windows Hello)
- **Session management**: 7-day sessions stored as signed cookies
- **Multiple credentials**: Register backup keys for account recovery

### Development Without Hardware Keys

For local development, use your browser's virtual authenticator:

**Chrome/Chromium:**

1. Open DevTools (F12)
2. Go to "Application" tab → "WebAuthn" section
3. Check "Enable virtual authenticator environment"
4. Add a new authenticator (select "ctap2" protocol)
5. The virtual authenticator will respond to WebAuthn prompts

**Firefox:**

1. Navigate to `about:config`
2. Set `security.webauthn.softtoken` to `true`
3. Firefox will simulate a platform authenticator

### Auth Flow

```
App loads → AuthGate checks session → Valid? → Show app
                                    → Invalid? → Show LoginPrompt
                                              → User authenticates with security key
                                              → Session created → Show app
```

### Environment Variables Reference

| Variable                | Required  | Description                                                |
| ----------------------- | --------- | ---------------------------------------------------------- |
| `AUTH_RP_ID`            | Yes       | Domain for WebAuthn. Use `localhost` for dev.              |
| `AUTH_ORIGIN`           | Yes       | Full origin URL. Use `http://localhost:5173` for dev.      |
| `AUTH_CREDENTIALS_PATH` | Yes       | Path to store credentials JSON file.                       |
| `AUTH_SESSION_SECRET`   | Yes       | Min 32 chars. HMAC secret for session signing.             |
| `AUTH_BOOTSTRAP_TOKEN`  | First run | One-time token for initial enrollment. Remove after setup. |

### Credential Management

Once authenticated, you can manage security keys:

- **Add keys**: Register additional hardware keys as backups
- **Rename keys**: Give friendly names to identify your keys
- **Remove keys**: Delete keys (cannot remove last remaining key)

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
