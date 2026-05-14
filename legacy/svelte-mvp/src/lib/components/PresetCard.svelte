<script lang="ts">
	/**
	 * PresetCard component for displaying a single preset.
	 * Task 50: Display preset name and total macros
	 * Tap to apply, edit/delete actions
	 */
	import type { Preset } from '$lib/types/index.js';

	interface Props {
		preset: Preset;
		onApply: (preset: Preset) => void;
		onEdit: (preset: Preset) => void;
		onDelete: (preset: Preset) => void;
	}

	let { preset, onApply, onEdit, onDelete }: Props = $props();

	/**
	 * Handle tap on the card to apply preset.
	 */
	function handleApply() {
		onApply(preset);
	}

	/**
	 * Handle edit button click.
	 * Prevent propagation to avoid triggering apply.
	 */
	function handleEdit(event: Event) {
		event.stopPropagation();
		onEdit(preset);
	}

	/**
	 * Handle delete button click.
	 * Prevent propagation to avoid triggering apply.
	 */
	function handleDelete(event: Event) {
		event.stopPropagation();
		onDelete(preset);
	}

	/**
	 * Handle keyboard activation for the card.
	 */
	function handleKeyDown(event: KeyboardEvent) {
		if (event.key === 'Enter' || event.key === ' ') {
			event.preventDefault();
			handleApply();
		}
	}
</script>

<div
	role="button"
	tabindex="0"
	onclick={handleApply}
	onkeydown={handleKeyDown}
	class="w-full rounded-lg bg-white/5 p-4 text-left hover:bg-white/10 focus:outline-none focus:ring-2 focus:ring-brand-accent min-h-[44px] cursor-pointer"
>
	<div class="flex items-start justify-between gap-2">
		<!-- Preset info -->
		<div class="flex-1 min-w-0">
			<div class="flex items-center gap-2 mb-1">
				<span class="text-base font-medium text-white truncate">{preset.name}</span>
				<span class="shrink-0 rounded px-1.5 py-0.5 text-xs bg-white/10 text-white/60">
					{preset.category}
				</span>
			</div>

			<!-- Macro totals -->
			<div class="flex gap-4 text-sm">
				<span>
					<span class="text-white/50">C</span>
					<span class="text-brand-accent font-semibold">{Math.round(preset.totalCarbs)}g</span>
				</span>
				<span>
					<span class="text-white/50">P</span>
					<span class="text-white">{Math.round(preset.totalProtein)}g</span>
				</span>
				<span>
					<span class="text-white/50">F</span>
					<span class="text-white">{Math.round(preset.totalFat)}g</span>
				</span>
			</div>

			<!-- Item count -->
			<div class="mt-1 text-xs text-white/40">
				{preset.items.length} {preset.items.length === 1 ? 'item' : 'items'}
			</div>
		</div>

		<!-- Action buttons -->
		<div class="flex gap-1 shrink-0">
			<button
				type="button"
				onclick={handleEdit}
				class="min-w-[44px] min-h-[44px] flex items-center justify-center rounded-lg text-white/50 hover:bg-white/10 hover:text-white"
				aria-label="Edit preset"
			>
				<svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
					<path d="M17.414 2.586a2 2 0 00-2.828 0L7 10.172V13h2.828l7.586-7.586a2 2 0 000-2.828z" />
					<path fill-rule="evenodd" d="M2 6a2 2 0 012-2h4a1 1 0 010 2H4v10h10v-4a1 1 0 112 0v4a2 2 0 01-2 2H4a2 2 0 01-2-2V6z" clip-rule="evenodd" />
				</svg>
			</button>
			<button
				type="button"
				onclick={handleDelete}
				class="min-w-[44px] min-h-[44px] flex items-center justify-center rounded-lg text-red-400/70 hover:bg-red-600/20 hover:text-red-400"
				aria-label="Delete preset"
			>
				<svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
					<path fill-rule="evenodd" d="M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9zM7 8a1 1 0 012 0v6a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v6a1 1 0 102 0V8a1 1 0 00-1-1z" clip-rule="evenodd" />
				</svg>
			</button>
		</div>
	</div>
</div>
