<script lang="ts">
	/**
	 * ManualEntryCTA component.
	 * Shown when food recognition is not configured, directing users
	 * to manual entry or the setup guide for configuring recognition.
	 */
</script>

<div class="flex flex-col gap-3 rounded-lg bg-white/5 px-4 py-4">
	<p class="text-sm font-medium text-white/80">Food recognition is not configured.</p>

	<a
		href="/manual"
		class="inline-flex items-center gap-1 text-sm font-semibold text-brand-accent hover:underline"
	>
		Enter meal manually &rarr;
	</a>

	<p class="text-xs text-white/50">
		To enable AI food recognition, set <code class="rounded bg-white/10 px-1 py-0.5">RECOGNITION_BASE_URL</code>
		and <code class="rounded bg-white/10 px-1 py-0.5">RECOGNITION_MODEL</code> in your
		<code class="rounded bg-white/10 px-1 py-0.5">.env</code> file.
		See the <a href="/docs/setup" class="underline hover:text-white/70">setup guide</a> for details.
	</p>
</div>
