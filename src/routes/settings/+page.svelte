<script lang="ts">
  import { Button, Input, ExpandableSection } from '$lib/components/ui';
  import { settingsStore } from '$lib/stores';
  import type { AIProvider, InsulinType, BSLUnit } from '$lib/types';

  // ML Model Config
  let foundryKey = $state(settingsStore.settings.foundryConfig?.apiKey || '');
  let foundryEndpoint = $state(settingsStore.settings.foundryConfig?.endpoint || '');
  let foundryModel = $state(settingsStore.settings.foundryConfig?.model || '');
  let openaiKey = $state(settingsStore.settings.openaiApiKey || '');
  let geminiKey = $state(settingsStore.settings.geminiApiKey || '');
  let claudeKey = $state(settingsStore.settings.claudeApiKey || '');
  let selectedProvider = $state<AIProvider | ''>(settingsStore.settings.aiProvider || '');

  // Metrics
  let defaultInsulinType = $state<InsulinType>(settingsStore.settings.defaultInsulinType);
  let defaultBSLUnit = $state<BSLUnit>(settingsStore.settings.defaultBSLUnit);

  // UI State
  let saving = $state(false);
  let saved = $state(false);

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
