<script lang="ts">
  import { Button } from '$lib/components/ui';
  import { settingsStore } from '$lib/stores';
  import type { MLProvider, InsulinType, BSLUnit } from '$lib/types';

  // Cloud API keys
  let openaiKey = $state(settingsStore.settings.openaiApiKey || '');
  let geminiKey = $state(settingsStore.settings.geminiApiKey || '');
  let claudeKey = $state(settingsStore.settings.claudeApiKey || '');

  // Microsoft Foundry
  let foundryEndpoint = $state(settingsStore.settings.foundryEndpoint || '');
  let foundryKey = $state(settingsStore.settings.foundryApiKey || '');

  // Self-hosted Ollama
  let ollamaEndpoint = $state(settingsStore.settings.ollamaEndpoint || 'http://localhost:11434');
  let ollamaModel = $state(settingsStore.settings.ollamaModel || '');

  let selectedProvider = $state<MLProvider | ''>(settingsStore.settings.aiProvider || '');
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
        foundryEndpoint: foundryEndpoint || undefined,
        foundryApiKey: foundryKey || undefined,
        ollamaEndpoint: ollamaEndpoint || undefined,
        ollamaModel: ollamaModel || undefined,
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

  // Test Ollama connection
  let ollamaStatus = $state<'idle' | 'testing' | 'success' | 'error'>('idle');
  let ollamaError = $state('');

  async function testOllamaConnection() {
    ollamaStatus = 'testing';
    ollamaError = '';
    try {
      const response = await fetch(`${ollamaEndpoint}/api/tags`);
      if (response.ok) {
        ollamaStatus = 'success';
      } else {
        ollamaStatus = 'error';
        ollamaError = `HTTP ${response.status}`;
      }
    } catch (e) {
      ollamaStatus = 'error';
      ollamaError = e instanceof Error ? e.message : 'Connection failed';
    }
  }
</script>

<div class="px-4 py-6">
  <header class="mb-8">
    <h1 class="text-2xl font-bold text-white">Settings</h1>
  </header>

  <div class="space-y-8">
    <!-- ML Configuration -->
    <section>
      <h2 class="mb-4 text-lg font-semibold text-gray-200">ML Config</h2>
      <p class="mb-4 text-sm text-gray-400">
        Configure ML providers for food recognition. Keys are stored locally on your device.
      </p>

      <!-- Provider Selection -->
      <div class="mb-6">
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
          <option value="foundry">Microsoft Foundry</option>
          <option value="ollama">Ollama (Self-hosted)</option>
        </select>
      </div>

      <!-- Cloud Providers -->
      <div class="mb-6 rounded-lg border border-gray-700 p-4">
        <h3 class="mb-3 text-sm font-medium text-gray-300">Cloud Providers</h3>

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
      </div>

      <!-- Microsoft Foundry -->
      <div class="mb-6 rounded-lg border border-gray-700 p-4">
        <h3 class="mb-3 text-sm font-medium text-gray-300">Microsoft Foundry</h3>
        <p class="mb-3 text-xs text-gray-500">
          Azure AI Foundry endpoint and API key for vision models.
        </p>

        <div class="mb-4">
          <label for="foundry-endpoint" class="mb-2 block text-sm font-medium text-gray-400">
            Endpoint URL
          </label>
          <input
            id="foundry-endpoint"
            type="url"
            bind:value={foundryEndpoint}
            placeholder="https://<service>.services.ai.azure.com/api/projects/<project>"
            class="w-full rounded-lg border border-gray-700 bg-gray-800 px-4 py-3 text-sm text-white placeholder-gray-500 focus:border-brand-accent focus:outline-none focus:ring-1 focus:ring-brand-accent"
          />
        </div>

        <div>
          <label for="foundry-key" class="mb-2 block text-sm font-medium text-gray-400">
            API Key
          </label>
          <input
            id="foundry-key"
            type="password"
            bind:value={foundryKey}
            placeholder="Your Foundry API key"
            class="w-full rounded-lg border border-gray-700 bg-gray-800 px-4 py-3 text-white placeholder-gray-500 focus:border-brand-accent focus:outline-none focus:ring-1 focus:ring-brand-accent"
          />
          {#if settingsStore.settings.foundryApiKey}
            <p class="mt-1 text-xs text-gray-500">
              Current: {maskKey(settingsStore.settings.foundryApiKey)}
            </p>
          {/if}
        </div>
      </div>

      <!-- Self-hosted Ollama -->
      <div class="mb-6 rounded-lg border border-gray-700 p-4">
        <h3 class="mb-3 text-sm font-medium text-gray-300">Ollama (Self-hosted)</h3>
        <p class="mb-3 text-xs text-gray-500">
          Connect to a local or self-hosted Ollama instance for privacy-focused inference.
        </p>

        <div class="mb-4">
          <label for="ollama-endpoint" class="mb-2 block text-sm font-medium text-gray-400">
            Endpoint URL
          </label>
          <div class="flex gap-2">
            <input
              id="ollama-endpoint"
              type="url"
              bind:value={ollamaEndpoint}
              placeholder="http://localhost:11434"
              class="flex-1 rounded-lg border border-gray-700 bg-gray-800 px-4 py-3 text-white placeholder-gray-500 focus:border-brand-accent focus:outline-none focus:ring-1 focus:ring-brand-accent"
            />
            <button
              type="button"
              onclick={testOllamaConnection}
              disabled={ollamaStatus === 'testing'}
              class="rounded-lg bg-gray-700 px-4 py-3 text-sm text-gray-300 transition-colors hover:bg-gray-600 disabled:opacity-50"
            >
              {ollamaStatus === 'testing' ? 'Testing...' : 'Test'}
            </button>
          </div>
          {#if ollamaStatus === 'success'}
            <p class="mt-1 text-xs text-green-400">Connected successfully</p>
          {:else if ollamaStatus === 'error'}
            <p class="mt-1 text-xs text-red-400">Failed: {ollamaError}</p>
          {/if}
        </div>

        <div>
          <label for="ollama-model" class="mb-2 block text-sm font-medium text-gray-400">
            Vision Model
          </label>
          <input
            id="ollama-model"
            type="text"
            bind:value={ollamaModel}
            placeholder="llava, bakllava, llava-llama3"
            class="w-full rounded-lg border border-gray-700 bg-gray-800 px-4 py-3 text-white placeholder-gray-500 focus:border-brand-accent focus:outline-none focus:ring-1 focus:ring-brand-accent"
          />
          <p class="mt-1 text-xs text-gray-500">
            Use a vision-capable model like llava or bakllava for food recognition.
          </p>
        </div>
      </div>
    </section>

    <!-- Defaults -->
    <section>
      <h2 class="mb-4 text-lg font-semibold text-gray-200">Defaults</h2>

      <div class="mb-4">
        <span id="insulin-type-label" class="mb-2 block text-sm font-medium text-gray-400"
          >Default Insulin Type</span
        >
        <div class="grid grid-cols-2 gap-2" role="group" aria-labelledby="insulin-type-label">
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
      </div>

      <div class="mb-4">
        <span id="bsl-unit-label" class="mb-2 block text-sm font-medium text-gray-400"
          >Blood Sugar Unit</span
        >
        <div class="grid grid-cols-2 gap-2" role="group" aria-labelledby="bsl-unit-label">
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
      </div>
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
