<script lang="ts">
  import { Button, Input, ExpandableSection } from '$lib/components/ui';
  import { settingsStore } from '$lib/stores';
  import type {
    AIProvider,
    InsulinType,
    BSLUnit,
    LocalModelConfig,
    CGMApiProvider,
    User,
    StoredCredential
  } from '$lib/types';
  import { isWebAuthnSupported, isPlatformAuthenticatorAvailable } from '$lib/types';
  import { CGM_PROVIDERS, createCGMApiService } from '$lib/services/cgm';
  import { getAuthService } from '$lib/services/auth';

  // ML Model Config
  let foundryKey = $state(settingsStore.settings.foundryConfig?.apiKey || '');
  let foundryEndpoint = $state(settingsStore.settings.foundryConfig?.endpoint || '');
  let foundryModel = $state(settingsStore.settings.foundryConfig?.model || '');
  let openaiKey = $state(settingsStore.settings.openaiApiKey || '');
  let geminiKey = $state(settingsStore.settings.geminiApiKey || '');
  let claudeKey = $state(settingsStore.settings.claudeApiKey || '');
  let selectedProvider = $state<AIProvider | ''>(settingsStore.settings.aiProvider || '');

  // Local Model Config (Ollama/LLaVA)
  let localEndpoint = $state(settingsStore.settings.localModelConfig?.endpoint || '');
  let localModelName = $state(settingsStore.settings.localModelConfig?.modelName || 'llava');
  let localModelType = $state<LocalModelConfig['type']>(
    settingsStore.settings.localModelConfig?.type || 'ollama'
  );
  let localTestStatus = $state<'idle' | 'testing' | 'success' | 'error'>('idle');
  let localTestMessage = $state('');

  // CGM API Config (Task 22)
  let cgmProvider = $state<CGMApiProvider | ''>(
    settingsStore.settings.cgmApiConfig?.provider || ''
  );
  let libreEmail = $state(settingsStore.settings.cgmApiConfig?.libreLink?.email || '');
  let librePassword = $state(settingsStore.settings.cgmApiConfig?.libreLink?.password || '');
  let libreRegion = $state(settingsStore.settings.cgmApiConfig?.libreLink?.region || 'us');
  let dexcomUsername = $state(settingsStore.settings.cgmApiConfig?.dexcomShare?.username || '');
  let dexcomPassword = $state(settingsStore.settings.cgmApiConfig?.dexcomShare?.password || '');
  let dexcomRegion = $state<'us' | 'ous'>(
    settingsStore.settings.cgmApiConfig?.dexcomShare?.region || 'us'
  );
  let cgmTestStatus = $state<'idle' | 'testing' | 'success' | 'error'>('idle');
  let cgmTestMessage = $state('');

  // Metrics
  let defaultInsulinType = $state<InsulinType>(settingsStore.settings.defaultInsulinType);
  let defaultBSLUnit = $state<BSLUnit>(settingsStore.settings.defaultBSLUnit);

  // UI State
  let saving = $state(false);
  let saved = $state(false);

  // Authentication (Task 24)
  let webAuthnSupported = $state(false);
  let platformAuthAvailable = $state(false);
  let authUsers = $state<User[]>([]);
  let authCredentials = $state<StoredCredential[]>([]);
  let currentUser = $state<User | null>(null);
  let authEnabled = $state(false);
  let authStatus = $state<'idle' | 'registering' | 'adding' | 'success' | 'error'>('idle');
  let authMessage = $state('');
  let newUsername = $state('');
  let newDisplayName = $state('');

  // Load auth status on mount
  $effect(() => {
    loadAuthStatus();
  });

  async function loadAuthStatus() {
    webAuthnSupported = isWebAuthnSupported();
    platformAuthAvailable = await isPlatformAuthenticatorAvailable();

    if (webAuthnSupported) {
      const authService = getAuthService();
      authUsers = authService.getUsers();
      const session = authService.getCurrentSession();
      if (session) {
        currentUser = authService.getUser(session.userId);
        if (currentUser) {
          authCredentials = authService.getUserCredentials(currentUser.id);
        }
      }
      authEnabled = authService.getConfig().enabled;
    }
  }

  async function registerUser() {
    if (!newUsername || !newDisplayName) return;

    authStatus = 'registering';
    authMessage = '';

    try {
      const authService = getAuthService();
      const user = await authService.registerUser(newUsername, newDisplayName);
      currentUser = user;
      authUsers = authService.getUsers();
      authCredentials = authService.getUserCredentials(user.id);
      authStatus = 'success';
      authMessage = `Registered ${user.displayName} successfully`;
      newUsername = '';
      newDisplayName = '';
    } catch (error) {
      authStatus = 'error';
      authMessage = error instanceof Error ? error.message : 'Registration failed';
    }
  }

  async function addCredential() {
    if (!currentUser) return;

    authStatus = 'adding';
    authMessage = '';

    try {
      const authService = getAuthService();
      await authService.addCredential(currentUser.id);
      authCredentials = authService.getUserCredentials(currentUser.id);
      authStatus = 'success';
      authMessage = 'Security key added successfully';
    } catch (error) {
      authStatus = 'error';
      authMessage = error instanceof Error ? error.message : 'Failed to add credential';
    }
  }

  function deleteCredential(credentialId: string) {
    if (!currentUser) return;
    const authService = getAuthService();
    authService.deleteCredential(credentialId);
    authCredentials = authService.getUserCredentials(currentUser.id);
  }

  function logout() {
    const authService = getAuthService();
    authService.logout();
    currentUser = null;
    authCredentials = [];
  }

  function toggleAuth() {
    const authService = getAuthService();
    authEnabled = !authEnabled;
    authService.setConfig({ enabled: authEnabled });
  }

  async function saveSettings() {
    saving = true;
    saved = false;
    try {
      await settingsStore.update({
        foundryConfig:
          foundryKey || foundryEndpoint
            ? {
                apiKey: foundryKey || undefined,
                endpoint: foundryEndpoint || undefined,
                model: foundryModel || undefined
              }
            : undefined,
        openaiApiKey: openaiKey || undefined,
        geminiApiKey: geminiKey || undefined,
        claudeApiKey: claudeKey || undefined,
        localModelConfig: localEndpoint
          ? {
              endpoint: localEndpoint,
              modelName: localModelName || 'llava',
              type: localModelType || 'ollama'
            }
          : undefined,
        aiProvider: selectedProvider || undefined,
        cgmApiConfig: cgmProvider
          ? {
              provider: cgmProvider,
              libreLink:
                cgmProvider === 'librelink' && libreEmail && librePassword
                  ? {
                      email: libreEmail,
                      password: librePassword,
                      region: libreRegion as 'us' | 'eu' | 'ae' | 'ap' | 'au' | 'ca' | 'de' | 'fr'
                    }
                  : undefined,
              dexcomShare:
                cgmProvider === 'dexcom-share' && dexcomUsername && dexcomPassword
                  ? { username: dexcomUsername, password: dexcomPassword, region: dexcomRegion }
                  : undefined
            }
          : undefined,
        defaultInsulinType,
        defaultBSLUnit
      });
      saved = true;
      setTimeout(() => (saved = false), 2000);
    } finally {
      saving = false;
    }
  }

  async function testLocalConnection() {
    localTestStatus = 'testing';
    localTestMessage = '';

    try {
      const endpoint = localEndpoint.replace(/\/$/, '');

      if (localModelType === 'ollama') {
        // Test Ollama API by listing models
        const response = await fetch(`${endpoint}/tags`, {
          method: 'GET',
          headers: { 'Content-Type': 'application/json' }
        });

        if (!response.ok) {
          throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }

        const data = await response.json();
        const models = data.models?.map((m: { name: string }) => m.name) || [];
        const hasModel = models.some((m: string) => m.includes(localModelName));

        if (hasModel) {
          localTestStatus = 'success';
          localTestMessage = `Connected. Found ${localModelName} among ${models.length} models.`;
        } else {
          localTestStatus = 'success';
          localTestMessage = `Connected. Model "${localModelName}" not found. Available: ${models.slice(0, 3).join(', ')}${models.length > 3 ? '...' : ''}`;
        }
      } else {
        // Test OpenAI-compatible API (LM Studio, etc.)
        const response = await fetch(`${endpoint}/models`, {
          method: 'GET',
          headers: { 'Content-Type': 'application/json' }
        });

        if (!response.ok) {
          throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }

        const data = await response.json();
        localTestStatus = 'success';
        localTestMessage = `Connected. ${data.data?.length || 0} models available.`;
      }
    } catch (error) {
      localTestStatus = 'error';
      localTestMessage =
        error instanceof Error
          ? error.message
          : 'Connection failed. Check endpoint and ensure server is running.';
    }
  }

  function maskKey(key: string): string {
    if (!key || key.length < 8) return key;
    return key.slice(0, 4) + '...' + key.slice(-4);
  }

  async function testCGMConnection() {
    cgmTestStatus = 'testing';
    cgmTestMessage = '';

    try {
      if (!cgmProvider) {
        throw new Error('Please select a CGM provider');
      }

      const config = {
        provider: cgmProvider as CGMApiProvider,
        libreLink:
          cgmProvider === 'librelink'
            ? {
                email: libreEmail,
                password: librePassword,
                region: libreRegion as 'us' | 'eu' | 'ae' | 'ap' | 'au' | 'ca' | 'de' | 'fr'
              }
            : undefined,
        dexcomShare:
          cgmProvider === 'dexcom-share'
            ? { username: dexcomUsername, password: dexcomPassword, region: dexcomRegion }
            : undefined
      };

      const service = createCGMApiService(config);
      if (!service) {
        throw new Error('Missing credentials for selected provider');
      }

      const status = await service.getConnectionStatus();

      if (status.isConnected) {
        cgmTestStatus = 'success';
        cgmTestMessage = status.patientName
          ? `Connected to ${status.patientName}`
          : 'Connection successful';
      } else {
        throw new Error(status.error || 'Connection failed');
      }
    } catch (error) {
      cgmTestStatus = 'error';
      cgmTestMessage =
        error instanceof Error
          ? error.message
          : 'Connection failed. Check credentials and ensure sharing is enabled.';
    }
  }
</script>

<div class="px-4 py-6">
  <header class="mb-8">
    <h1 class="text-2xl font-bold text-white">Settings</h1>
  </header>

  <div class="space-y-6">
    <!-- Metrics Section (formerly Defaults) -->
    <section>
      <h2 class="mb-4 text-lg font-semibold text-gray-200">Metrics</h2>

      <fieldset class="mb-4">
        <legend class="mb-2 block text-sm font-medium text-gray-400">Default Insulin Type</legend>
        <div class="grid grid-cols-2 gap-2">
          <Button
            variant={defaultInsulinType === 'bolus' ? 'primary' : 'secondary'}
            onclick={() => (defaultInsulinType = 'bolus')}
          >
            Bolus
          </Button>
          <Button
            variant={defaultInsulinType === 'basal' ? 'primary' : 'secondary'}
            onclick={() => (defaultInsulinType = 'basal')}
          >
            Basal
          </Button>
        </div>
      </fieldset>

      <fieldset class="mb-4">
        <legend class="mb-2 block text-sm font-medium text-gray-400">Blood Sugar Unit</legend>
        <div class="grid grid-cols-2 gap-2">
          <Button
            variant={defaultBSLUnit === 'mmol/L' ? 'primary' : 'secondary'}
            onclick={() => (defaultBSLUnit = 'mmol/L')}
          >
            mmol/L
          </Button>
          <Button
            variant={defaultBSLUnit === 'mg/dL' ? 'primary' : 'secondary'}
            onclick={() => (defaultBSLUnit = 'mg/dL')}
          >
            mg/dL
          </Button>
        </div>
      </fieldset>
    </section>

    <!-- ML Model Config (Collapsible) -->
    <ExpandableSection title="ML Model Config" subtitle="Configure ML Model" collapsed={true}>
      <!-- Provider Selection -->
      <div class="mb-4">
        <label for="provider" class="mb-2 block text-sm font-medium text-gray-400">
          Preferred Provider
        </label>
        <select
          id="provider"
          bind:value={selectedProvider}
          class="w-full rounded-lg border border-gray-700 bg-gray-800 px-4 py-3 text-white transition-colors focus:border-brand-accent focus:outline-none focus:ring-2 focus:ring-brand-accent/30"
        >
          <option value="">Auto-detect</option>
          <option value="foundry">Azure AI Foundry (Recommended)</option>
          <option value="openai">OpenAI</option>
          <option value="gemini">Google Gemini</option>
          <option value="claude">Anthropic Claude</option>
          <option value="azure">Azure OpenAI (Classic)</option>
          <option value="local">Local Model (Ollama/LLaVA)</option>
        </select>
      </div>

      <!-- Azure AI Foundry Config -->
      <div class="mb-6 rounded-lg border border-gray-800 bg-gray-900/30 p-4">
        <h3 class="mb-3 text-sm font-medium text-gray-300">Azure AI Foundry</h3>

        <div class="space-y-3">
          <Input
            type="password"
            label="API Key"
            bind:value={foundryKey}
            placeholder="Enter your API key"
          />
          {#if settingsStore.settings.foundryConfig?.apiKey}
            <p class="text-xs text-gray-500">
              Current: {maskKey(settingsStore.settings.foundryConfig.apiKey)}
            </p>
          {/if}

          <Input
            type="url"
            label="Endpoint"
            bind:value={foundryEndpoint}
            placeholder="https://your-resource.openai.azure.com"
          />

          <Input
            type="text"
            label="Model (optional)"
            bind:value={foundryModel}
            placeholder="gpt-4o"
          />
        </div>
      </div>

      <!-- OpenAI Config -->
      <div class="mb-4">
        <Input type="password" label="OpenAI API Key" bind:value={openaiKey} placeholder="sk-..." />
        {#if settingsStore.settings.openaiApiKey}
          <p class="mt-1 text-xs text-gray-500">
            Current: {maskKey(settingsStore.settings.openaiApiKey)}
          </p>
        {/if}
      </div>

      <!-- Gemini Config -->
      <div class="mb-4">
        <Input
          type="password"
          label="Google Gemini API Key"
          bind:value={geminiKey}
          placeholder="AIza..."
        />
        {#if settingsStore.settings.geminiApiKey}
          <p class="mt-1 text-xs text-gray-500">
            Current: {maskKey(settingsStore.settings.geminiApiKey)}
          </p>
        {/if}
      </div>

      <!-- Claude Config -->
      <div class="mb-4">
        <Input
          type="password"
          label="Anthropic Claude API Key"
          bind:value={claudeKey}
          placeholder="sk-ant-..."
        />
        {#if settingsStore.settings.claudeApiKey}
          <p class="mt-1 text-xs text-gray-500">
            Current: {maskKey(settingsStore.settings.claudeApiKey)}
          </p>
        {/if}
      </div>

      <!-- Local Model Config (Ollama/LLaVA) -->
      <div class="mb-6 rounded-lg border border-gray-800 bg-gray-900/30 p-4">
        <h3 class="mb-3 text-sm font-medium text-gray-300">Local Model (Offline)</h3>
        <p class="mb-4 text-xs text-gray-500">
          Run AI estimation locally using Ollama with LLaVA or compatible vision models. No internet
          required.
        </p>

        <div class="space-y-3">
          <div>
            <label for="localModelType" class="mb-2 block text-sm font-medium text-gray-400">
              Server Type
            </label>
            <select
              id="localModelType"
              bind:value={localModelType}
              class="w-full rounded-lg border border-gray-700 bg-gray-800 px-4 py-3 text-white transition-colors focus:border-brand-accent focus:outline-none focus:ring-2 focus:ring-brand-accent/30"
            >
              <option value="ollama">Ollama</option>
              <option value="lmstudio">LM Studio</option>
              <option value="openai-compatible">OpenAI-compatible</option>
            </select>
          </div>

          <Input
            type="url"
            label="Endpoint"
            bind:value={localEndpoint}
            placeholder={localModelType === 'ollama'
              ? 'http://localhost:11434/api'
              : 'http://localhost:1234/v1'}
          />
          {#if settingsStore.settings.localModelConfig?.endpoint}
            <p class="text-xs text-gray-500">
              Current: {settingsStore.settings.localModelConfig.endpoint}
            </p>
          {/if}

          <Input type="text" label="Model Name" bind:value={localModelName} placeholder="llava" />
          <p class="text-xs text-gray-500">
            Recommended: llava, llava-llama3, bakllava, or any vision-capable model
          </p>

          <!-- Connection Test -->
          <div class="pt-2">
            <Button
              variant="secondary"
              size="sm"
              onclick={testLocalConnection}
              disabled={!localEndpoint || localTestStatus === 'testing'}
            >
              {localTestStatus === 'testing' ? 'Testing...' : 'Test Connection'}
            </Button>

            {#if localTestStatus === 'success'}
              <p class="mt-2 text-sm text-green-400">{localTestMessage}</p>
            {:else if localTestStatus === 'error'}
              <p class="mt-2 text-sm text-red-400">{localTestMessage}</p>
            {/if}
          </div>
        </div>
      </div>
    </ExpandableSection>

    <!-- CGM API Config (Task 22) -->
    <ExpandableSection
      title="CGM Integration"
      subtitle="Connect to your glucose monitor"
      collapsed={true}
    >
      <p class="mb-4 text-sm text-gray-400">
        Connect directly to your CGM to automatically sync glucose readings. Requires sharing to be
        enabled in your CGM app.
      </p>

      <!-- Provider Selection -->
      <div class="mb-4">
        <label for="cgmProvider" class="mb-2 block text-sm font-medium text-gray-400">
          CGM Provider
        </label>
        <select
          id="cgmProvider"
          bind:value={cgmProvider}
          class="w-full rounded-lg border border-gray-700 bg-gray-800 px-4 py-3 text-white transition-colors focus:border-brand-accent focus:outline-none focus:ring-2 focus:ring-brand-accent/30"
        >
          <option value="">Not configured</option>
          {#each CGM_PROVIDERS as provider}
            <option value={provider.value}>{provider.label}</option>
          {/each}
        </select>
      </div>

      <!-- LibreLink Config -->
      {#if cgmProvider === 'librelink'}
        <div class="mb-6 rounded-lg border border-gray-800 bg-gray-900/30 p-4">
          <h3 class="mb-3 text-sm font-medium text-gray-300">Freestyle Libre (LibreLinkUp)</h3>
          <p class="mb-4 text-xs text-gray-500">
            Enter your LibreLinkUp credentials. Enable sharing in your Libre app first.
          </p>

          <div class="space-y-3">
            <Input
              type="email"
              label="Email"
              bind:value={libreEmail}
              placeholder="your@email.com"
            />

            <Input
              type="password"
              label="Password"
              bind:value={librePassword}
              placeholder="LibreLinkUp password"
            />

            <div>
              <label for="libreRegion" class="mb-2 block text-sm font-medium text-gray-400">
                Region
              </label>
              <select
                id="libreRegion"
                bind:value={libreRegion}
                class="w-full rounded-lg border border-gray-700 bg-gray-800 px-4 py-3 text-white transition-colors focus:border-brand-accent focus:outline-none focus:ring-2 focus:ring-brand-accent/30"
              >
                <option value="us">United States</option>
                <option value="eu">Europe</option>
                <option value="au">Australia</option>
                <option value="ca">Canada</option>
                <option value="de">Germany</option>
                <option value="fr">France</option>
                <option value="ae">Middle East</option>
                <option value="ap">Asia Pacific</option>
              </select>
            </div>
          </div>
        </div>
      {/if}

      <!-- Dexcom Share Config -->
      {#if cgmProvider === 'dexcom-share'}
        <div class="mb-6 rounded-lg border border-gray-800 bg-gray-900/30 p-4">
          <h3 class="mb-3 text-sm font-medium text-gray-300">Dexcom Share</h3>
          <p class="mb-4 text-xs text-gray-500">
            Enter your Dexcom Share credentials. Enable sharing in your Dexcom app first.
          </p>

          <div class="space-y-3">
            <Input
              type="text"
              label="Username"
              bind:value={dexcomUsername}
              placeholder="Dexcom username"
            />

            <Input
              type="password"
              label="Password"
              bind:value={dexcomPassword}
              placeholder="Dexcom password"
            />

            <div>
              <label for="dexcomRegion" class="mb-2 block text-sm font-medium text-gray-400">
                Region
              </label>
              <select
                id="dexcomRegion"
                bind:value={dexcomRegion}
                class="w-full rounded-lg border border-gray-700 bg-gray-800 px-4 py-3 text-white transition-colors focus:border-brand-accent focus:outline-none focus:ring-2 focus:ring-brand-accent/30"
              >
                <option value="us">United States</option>
                <option value="ous">International (Outside US)</option>
              </select>
            </div>
          </div>
        </div>
      {/if}

      <!-- Connection Test -->
      {#if cgmProvider}
        <div class="pt-2">
          <Button
            variant="secondary"
            size="sm"
            onclick={testCGMConnection}
            disabled={cgmTestStatus === 'testing'}
          >
            {cgmTestStatus === 'testing' ? 'Testing...' : 'Test Connection'}
          </Button>

          {#if cgmTestStatus === 'success'}
            <p class="mt-2 text-sm text-green-400">{cgmTestMessage}</p>
          {:else if cgmTestStatus === 'error'}
            <p class="mt-2 text-sm text-red-400">{cgmTestMessage}</p>
          {/if}
        </div>
      {/if}
    </ExpandableSection>

    <!-- Authentication (Task 24) -->
    <ExpandableSection title="Security" subtitle="FIDO/YubiKey authentication" collapsed={true}>
      {#if !webAuthnSupported}
        <div class="rounded-lg bg-yellow-500/20 px-4 py-3 text-yellow-400">
          WebAuthn is not supported in this browser. Use a modern browser like Chrome, Firefox, or
          Safari.
        </div>
      {:else}
        <p class="mb-4 text-sm text-gray-400">
          Secure your data with passwordless authentication using a YubiKey, passkey, or other
          FIDO2-compatible security key.
        </p>

        <!-- Auth Toggle -->
        <div class="mb-4 flex items-center justify-between rounded-lg bg-gray-800 p-4">
          <div>
            <h3 class="font-medium text-white">Enable Authentication</h3>
            <p class="text-sm text-gray-400">Require security key to access app</p>
          </div>
          <button
            type="button"
            class="relative h-6 w-11 rounded-full transition-colors {authEnabled
              ? 'bg-brand-accent'
              : 'bg-gray-600'}"
            onclick={toggleAuth}
          >
            <span
              class="absolute left-0.5 top-0.5 h-5 w-5 rounded-full bg-white transition-transform {authEnabled
                ? 'translate-x-5'
                : ''}"
            ></span>
          </button>
        </div>

        <!-- Platform Authenticator Info -->
        {#if platformAuthAvailable}
          <p class="mb-4 text-xs text-green-400">
            Platform authenticator available (Touch ID, Face ID, Windows Hello)
          </p>
        {/if}

        <!-- Current User -->
        {#if currentUser}
          <div class="mb-4 rounded-lg border border-gray-800 bg-gray-900/30 p-4">
            <div class="flex items-center justify-between">
              <div>
                <h3 class="font-medium text-white">{currentUser.displayName}</h3>
                <p class="text-sm text-gray-400">@{currentUser.username}</p>
              </div>
              <Button variant="secondary" size="sm" onclick={logout}>Logout</Button>
            </div>

            <!-- Registered Credentials -->
            <div class="mt-4">
              <h4 class="mb-2 text-sm font-medium text-gray-400">Security Keys</h4>
              {#if authCredentials.length === 0}
                <p class="text-sm text-gray-500">No security keys registered</p>
              {:else}
                <div class="space-y-2">
                  {#each authCredentials as credential}
                    <div class="flex items-center justify-between rounded bg-gray-800 px-3 py-2">
                      <div>
                        <p class="text-sm text-white">
                          {credential.friendlyName || 'Security Key'}
                        </p>
                        <p class="text-xs text-gray-500">
                          Added {new Date(credential.createdAt).toLocaleDateString()}
                        </p>
                      </div>
                      <button
                        type="button"
                        class="text-red-400 hover:text-red-300"
                        onclick={() => deleteCredential(credential.credentialId)}
                      >
                        Remove
                      </button>
                    </div>
                  {/each}
                </div>
              {/if}

              <Button
                variant="secondary"
                size="sm"
                class="mt-3"
                onclick={addCredential}
                disabled={authStatus === 'adding'}
              >
                {authStatus === 'adding' ? 'Adding...' : 'Add Security Key'}
              </Button>
            </div>
          </div>
        {:else}
          <!-- Registration Form -->
          <div class="mb-4 rounded-lg border border-gray-800 bg-gray-900/30 p-4">
            <h3 class="mb-3 text-sm font-medium text-gray-300">Register New User</h3>
            <div class="space-y-3">
              <Input
                type="text"
                label="Username"
                bind:value={newUsername}
                placeholder="e.g., john"
              />
              <Input
                type="text"
                label="Display Name"
                bind:value={newDisplayName}
                placeholder="e.g., John Doe"
              />
              <Button
                variant="primary"
                size="sm"
                onclick={registerUser}
                disabled={!newUsername || !newDisplayName || authStatus === 'registering'}
              >
                {authStatus === 'registering' ? 'Registering...' : 'Register with Security Key'}
              </Button>
            </div>
          </div>
        {/if}

        <!-- Status Messages -->
        {#if authStatus === 'success'}
          <p class="mt-2 text-sm text-green-400">{authMessage}</p>
        {:else if authStatus === 'error'}
          <p class="mt-2 text-sm text-red-400">{authMessage}</p>
        {/if}

        <!-- Existing Users -->
        {#if authUsers.length > 0 && !currentUser}
          <div class="mt-4">
            <h4 class="mb-2 text-sm font-medium text-gray-400">Existing Users</h4>
            <div class="space-y-2">
              {#each authUsers as user}
                <div class="flex items-center justify-between rounded bg-gray-800 px-3 py-2">
                  <div>
                    <p class="text-sm text-white">{user.displayName}</p>
                    <p class="text-xs text-gray-500">@{user.username}</p>
                  </div>
                </div>
              {/each}
            </div>
          </div>
        {/if}
      {/if}
    </ExpandableSection>

    <!-- Save Button -->
    <div class="pt-4">
      {#if saved}
        <div class="mb-4 rounded-lg bg-green-500/20 px-4 py-3 text-center text-green-400">
          Settings saved successfully
        </div>
      {/if}
      <Button variant="primary" size="lg" class="w-full" onclick={saveSettings} loading={saving}>
        Save Settings
      </Button>
    </div>

    <!-- App Info -->
    <section class="border-t border-gray-800 pt-6">
      <h2 class="mb-4 text-lg font-semibold text-gray-200">About</h2>
      <div class="text-sm text-gray-400">
        <p>MeData v0.0.1</p>
        <p class="mt-1">Personal health data tracking application</p>
      </div>
    </section>
  </div>
</div>
