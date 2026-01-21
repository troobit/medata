<script lang="ts">
  import { Button } from '$lib/components/ui';
  import { authStore, settingsStore } from '$lib/stores';
  import type { AIProvider, InsulinType, BSLUnit } from '$lib/types';

  let openaiKey = $state(settingsStore.settings.openaiApiKey || '');
  let geminiKey = $state(settingsStore.settings.geminiApiKey || '');
  let claudeKey = $state(settingsStore.settings.claudeApiKey || '');
  let selectedProvider = $state<AIProvider | ''>(settingsStore.settings.aiProvider || '');
  let defaultInsulinType = $state<InsulinType>(settingsStore.settings.defaultInsulinType);
  let defaultBSLUnit = $state<BSLUnit>(settingsStore.settings.defaultBSLUnit);
  let saving = $state(false);
  let saved = $state(false);

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

    <!-- Security -->
    <section class="border-t border-gray-800 pt-6">
      <h2 class="mb-4 text-lg font-semibold text-gray-200">Security</h2>
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
