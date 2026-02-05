<script lang="ts">
	// Future: These will navigate to capture/entry/preset flows
</script>

<div class="flex flex-col gap-4">
	<a
		href="/capture"
		class="flex items-center justify-center gap-2 min-h-[44px] px-6 py-4 bg-brand-accent text-primary-background font-semibold rounded-lg hover:opacity-90 transition-opacity"
	>
		Capture Meal
	</a>

	<a
		href="/manual"
		class="flex items-center justify-center gap-2 min-h-[44px] px-6 py-4 bg-white/10 text-white font-semibold rounded-lg hover:bg-white/20 transition-colors"
	>
		Manual Entry
	</a>

	<a
		href="/presets"
		class="flex items-center justify-center gap-2 min-h-[44px] px-6 py-4 bg-white/10 text-white font-semibold rounded-lg hover:bg-white/20 transition-colors"
	>
		From Preset
	</a>

	<hr class="border-white/10 my-4" />

	<section>
		<h2 class="text-lg font-medium text-white/70 mb-3">Logbook</h2>
		<p class="text-white/50 text-sm">No meals yet</p>
	</section>
</div>
