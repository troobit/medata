<script lang="ts">
  import { onMount } from 'svelte';
  import { startRegistration } from '@simplewebauthn/browser';
  import { Button } from '$lib/components/ui';
  import { authStore, settingsStore } from '$lib/stores';
  import { getServerAuthClient } from '$lib/services/auth/ServerAuthClient';
  import type { CredentialInfo } from '$lib/services/auth/ServerAuthClient';
  import type { AIProvider, InsulinType, BSLUnit } from '$lib/types';

  let openaiKey = $state(settingsStore.settings.openaiApiKey || '');
  let geminiKey = $state(settingsStore.settings.geminiApiKey || '');
  let claudeKey = $state(settingsStore.settings.claudeApiKey || '');
  let selectedProvider = $state<AIProvider | ''>(settingsStore.settings.aiProvider || '');
  let defaultInsulinType = $state<InsulinType>(settingsStore.settings.defaultInsulinType);
  let defaultBSLUnit = $state<BSLUnit>(settingsStore.settings.defaultBSLUnit);
  let saving = $state(false);
  let saved = $state(false);

  // Credential management state
  let credentials = $state<CredentialInfo[]>([]);
  let loadingCredentials = $state(true);
  let credentialError = $state<string | null>(null);
  let editingCredentialId = $state<string | null>(null);
  let editingName = $state('');
  let addingCredential = $state(false);
  let newCredentialName = $state('');
  let deletingCredentialId = $state<string | null>(null);

  const authClient = getServerAuthClient();

  onMount(async () => {
    await loadCredentials();
  });

  async function loadCredentials() {
    loadingCredentials = true;
    credentialError = null;
    try {
      const response = await authClient.listCredentials();
      credentials = response.credentials;
    } catch (error) {
      credentialError = error instanceof Error ? error.message : 'Failed to load credentials';
    } finally {
      loadingCredentials = false;
    }
  }

  async function saveSettings() {
    saving = true;
    saved = false;
    try {
      await settingsStore.update({
        openaiApiKey: openaiKey || undefined,
        geminiApiKey: geminiKey || undefined,
        claudeApiKey: claudeKey || undefined,
        aiProvider: selectedProvider || undefined,
        defaultInsulinType,
        defaultBSLUnit
      });
      saved = true;
      setTimeout(() => (saved = false), 2000);
    } finally {
      saving = false;
    }
  }

  function maskKey(key: string): string {
    if (!key || key.length < 8) return key;
    return key.slice(0, 4) + '...' + key.slice(-4);
  }

  function formatDate(dateStr: string | null): string {
    if (!dateStr) return 'Never';
    const date = new Date(dateStr);
    return date.toLocaleDateString(undefined, {
      year: 'numeric',
      month: 'short',
      day: 'numeric'
    });
  }

  function startEditing(cred: CredentialInfo) {
    editingCredentialId = cred.id;
    editingName = cred.friendlyName;
  }

  function cancelEditing() {
    editingCredentialId = null;
    editingName = '';
  }

  async function saveCredentialName(id: string) {
    if (!editingName.trim()) return;
    try {
      await authClient.updateCredential(id, editingName.trim());
      await loadCredentials();
      cancelEditing();
    } catch (error) {
      credentialError = error instanceof Error ? error.message : 'Failed to update credential';
    }
  }

  async function deleteCredential(id: string) {
    if (credentials.length <= 1) {
      credentialError = 'Cannot delete the last credential. Add another credential first.';
      return;
    }

    deletingCredentialId = id;
    try {
      await authClient.deleteCredential(id);
      await loadCredentials();
    } catch (error) {
      credentialError = error instanceof Error ? error.message : 'Failed to delete credential';
    } finally {
      deletingCredentialId = null;
    }
  }

  async function addNewCredential() {
    if (!newCredentialName.trim()) {
      credentialError = 'Please enter a name for the new credential';
      return;
    }

    addingCredential = true;
    credentialError = null;

    try {
      // Get registration options from server
      const options = await authClient.getRegistrationOptions();

      // Trigger WebAuthn registration
      const credential = await startRegistration({ optionsJSON: options });

      // Verify and store the credential
      await authClient.verifyRegistration(credential, newCredentialName.trim());

      // Reload credentials
      await loadCredentials();
      newCredentialName = '';
    } catch (error) {
      if (error instanceof Error && error.name === 'NotAllowedError') {
        credentialError = 'Registration was cancelled or timed out';
      } else {
        credentialError = error instanceof Error ? error.message : 'Failed to add credential';
      }
    } finally {
      addingCredential = false;
    }
  }
</script>

<div class="px-4 py-6">
  <header class="mb-8">
    <h1 class="text-2xl font-bold text-white">Settings</h1>
  </header>

  <div class="space-y-8">
    <!-- AI Configuration -->
    <section>
      <h2 class="mb-4 text-lg font-semibold text-gray-200">AI Configuration</h2>
      <p class="mb-4 text-sm text-gray-400">
        Configure API keys for AI-powered food recognition. Keys are stored locally on your device.
      </p>

      <!-- Provider Selection -->
      <div class="mb-4">
        <label for="provider" class="mb-2 block text-sm font-medium text-gray-400">
          Preferred Provider
        </label>
        <select
          id="provider"
          bind:value={selectedProvider}
          class="w-full rounded-lg border border-gray-700 bg-gray-800 px-4 py-3 text-white focus:border-brand-accent focus:outline-none focus:ring-1 focus:ring-brand-accent"
        >
          <option value="">Auto-detect</option>
          <option value="openai">OpenAI</option>
          <option value="gemini">Google Gemini</option>
          <option value="claude">Anthropic Claude</option>
        </select>
      </div>

      <!-- OpenAI Key -->
      <div class="mb-4">
        <label for="openai" class="mb-2 block text-sm font-medium text-gray-400">
          OpenAI API Key
        </label>
        <input
          id="openai"
          type="password"
          bind:value={openaiKey}
          placeholder="sk-..."
          class="w-full rounded-lg border border-gray-700 bg-gray-800 px-4 py-3 text-white placeholder-gray-500 focus:border-brand-accent focus:outline-none focus:ring-1 focus:ring-brand-accent"
        />
        {#if settingsStore.settings.openaiApiKey}
          <p class="mt-1 text-xs text-gray-500">
            Current: {maskKey(settingsStore.settings.openaiApiKey)}
          </p>
        {/if}
      </div>

      <!-- Gemini Key -->
      <div class="mb-4">
        <label for="gemini" class="mb-2 block text-sm font-medium text-gray-400">
          Google Gemini API Key
        </label>
        <input
          id="gemini"
          type="password"
          bind:value={geminiKey}
          placeholder="AIza..."
          class="w-full rounded-lg border border-gray-700 bg-gray-800 px-4 py-3 text-white placeholder-gray-500 focus:border-brand-accent focus:outline-none focus:ring-1 focus:ring-brand-accent"
        />
        {#if settingsStore.settings.geminiApiKey}
          <p class="mt-1 text-xs text-gray-500">
            Current: {maskKey(settingsStore.settings.geminiApiKey)}
          </p>
        {/if}
      </div>

      <!-- Claude Key -->
      <div class="mb-4">
        <label for="claude" class="mb-2 block text-sm font-medium text-gray-400">
          Anthropic Claude API Key
        </label>
        <input
          id="claude"
          type="password"
          bind:value={claudeKey}
          placeholder="sk-ant-..."
          class="w-full rounded-lg border border-gray-700 bg-gray-800 px-4 py-3 text-white placeholder-gray-500 focus:border-brand-accent focus:outline-none focus:ring-1 focus:ring-brand-accent"
        />
        {#if settingsStore.settings.claudeApiKey}
          <p class="mt-1 text-xs text-gray-500">
            Current: {maskKey(settingsStore.settings.claudeApiKey)}
          </p>
        {/if}
      </div>
    </section>

    <!-- Defaults -->
    <section>
      <h2 class="mb-4 text-lg font-semibold text-gray-200">Defaults</h2>

      <fieldset class="mb-4">
        <legend class="mb-2 block text-sm font-medium text-gray-400">Default Insulin Type</legend>
        <div class="grid grid-cols-2 gap-2">
          <button
            type="button"
            class="rounded-lg px-4 py-3 text-center font-medium transition-colors {defaultInsulinType ===
            'bolus'
              ? 'bg-blue-500 text-white'
              : 'bg-gray-800 text-gray-300 hover:bg-gray-700'}"
            onclick={() => (defaultInsulinType = 'bolus')}
          >
            Bolus
          </button>
          <button
            type="button"
            class="rounded-lg px-4 py-3 text-center font-medium transition-colors {defaultInsulinType ===
            'basal'
              ? 'bg-blue-500 text-white'
              : 'bg-gray-800 text-gray-300 hover:bg-gray-700'}"
            onclick={() => (defaultInsulinType = 'basal')}
          >
            Basal
          </button>
        </div>
      </fieldset>

      <fieldset class="mb-4">
        <legend class="mb-2 block text-sm font-medium text-gray-400">Blood Sugar Unit</legend>
        <div class="grid grid-cols-2 gap-2">
          <button
            type="button"
            class="rounded-lg px-4 py-3 text-center font-medium transition-colors {defaultBSLUnit ===
            'mmol/L'
              ? 'bg-yellow-500 text-gray-950'
              : 'bg-gray-800 text-gray-300 hover:bg-gray-700'}"
            onclick={() => (defaultBSLUnit = 'mmol/L')}
          >
            mmol/L
          </button>
          <button
            type="button"
            class="rounded-lg px-4 py-3 text-center font-medium transition-colors {defaultBSLUnit ===
            'mg/dL'
              ? 'bg-yellow-500 text-gray-950'
              : 'bg-gray-800 text-gray-300 hover:bg-gray-700'}"
            onclick={() => (defaultBSLUnit = 'mg/dL')}
          >
            mg/dL
          </button>
        </div>
      </fieldset>
    </section>

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

    <!-- Security Keys -->
    <section class="border-t border-gray-800 pt-6">
      <h2 class="mb-4 text-lg font-semibold text-gray-200">Security Keys</h2>
      <p class="mb-4 text-sm text-gray-400">
        Manage your registered hardware security keys. Add backup keys to prevent lockout.
      </p>

      {#if credentialError}
        <div class="mb-4 rounded-lg bg-red-500/20 px-4 py-3 text-sm text-red-400">
          {credentialError}
          <button
            type="button"
            class="ml-2 underline hover:no-underline"
            onclick={() => (credentialError = null)}
          >
            Dismiss
          </button>
        </div>
      {/if}

      {#if loadingCredentials}
        <div class="flex items-center justify-center py-8">
          <span
            class="inline-block h-6 w-6 animate-spin rounded-full border-2 border-gray-400 border-t-transparent"
          ></span>
          <span class="ml-2 text-gray-400">Loading credentials...</span>
        </div>
      {:else}
        <!-- Credentials List -->
        <div class="space-y-3">
          {#each credentials as cred (cred.id)}
            <div class="rounded-lg border border-gray-700 bg-gray-800 p-4">
              {#if editingCredentialId === cred.id}
                <!-- Edit Mode -->
                <div class="flex items-center gap-2">
                  <input
                    type="text"
                    bind:value={editingName}
                    class="flex-1 rounded-lg border border-gray-600 bg-gray-700 px-3 py-2 text-white focus:border-brand-accent focus:outline-none"
                    onkeydown={(e) => {
                      if (e.key === 'Enter') saveCredentialName(cred.id);
                      if (e.key === 'Escape') cancelEditing();
                    }}
                  />
                  <button
                    type="button"
                    class="rounded-lg bg-brand-accent px-3 py-2 text-sm font-medium text-gray-950 hover:bg-brand-accent/90"
                    onclick={() => saveCredentialName(cred.id)}
                  >
                    Save
                  </button>
                  <button
                    type="button"
                    class="rounded-lg bg-gray-700 px-3 py-2 text-sm font-medium text-gray-300 hover:bg-gray-600"
                    onclick={cancelEditing}
                  >
                    Cancel
                  </button>
                </div>
              {:else}
                <!-- View Mode -->
                <div class="flex items-start justify-between">
                  <div>
                    <h3 class="font-medium text-white">{cred.friendlyName}</h3>
                    <div class="mt-1 space-y-0.5 text-xs text-gray-400">
                      <p>Added: {formatDate(cred.createdAt)}</p>
                      <p>Last used: {formatDate(cred.lastUsedAt)}</p>
                      <p class="capitalize">Type: {cred.deviceType.replace('_', ' ')}</p>
                    </div>
                  </div>
                  <div class="flex gap-2">
                    <button
                      type="button"
                      class="rounded-lg px-3 py-1.5 text-sm text-gray-400 hover:bg-gray-700 hover:text-white"
                      onclick={() => startEditing(cred)}
                    >
                      Edit
                    </button>
                    <button
                      type="button"
                      class="rounded-lg px-3 py-1.5 text-sm text-red-400 hover:bg-red-500/20 hover:text-red-300 disabled:cursor-not-allowed disabled:opacity-50"
                      disabled={credentials.length <= 1 || deletingCredentialId === cred.id}
                      onclick={() => deleteCredential(cred.id)}
                    >
                      {deletingCredentialId === cred.id ? 'Deleting...' : 'Delete'}
                    </button>
                  </div>
                </div>
              {/if}
            </div>
          {/each}
        </div>

        <!-- Add New Credential -->
        <div class="mt-4 rounded-lg border border-dashed border-gray-600 p-4">
          <h4 class="mb-2 text-sm font-medium text-gray-300">Add New Security Key</h4>
          <div class="flex gap-2">
            <input
              type="text"
              bind:value={newCredentialName}
              placeholder="Key name (e.g., Backup YubiKey)"
              class="flex-1 rounded-lg border border-gray-600 bg-gray-700 px-3 py-2 text-white placeholder-gray-500 focus:border-brand-accent focus:outline-none"
              disabled={addingCredential}
            />
            <Button
              variant="secondary"
              size="md"
              onclick={addNewCredential}
              loading={addingCredential}
              disabled={addingCredential || !newCredentialName.trim()}
            >
              Add Key
            </Button>
          </div>
          <p class="mt-2 text-xs text-gray-500">
            Insert your security key and click "Add Key" to register it as a backup.
          </p>
        </div>
      {/if}
    </section>

    <!-- Logout -->
    <section class="border-t border-gray-800 pt-6">
      <h2 class="mb-4 text-lg font-semibold text-gray-200">Session</h2>
      <p class="mb-4 text-sm text-gray-400">
        You are currently authenticated. Logging out will require you to use your security key
        again.
      </p>
      <Button
        variant="secondary"
        size="md"
        class="w-full"
        onclick={() => authStore.logout()}
        loading={authStore.loading}
      >
        Logout
      </Button>
    </section>

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
