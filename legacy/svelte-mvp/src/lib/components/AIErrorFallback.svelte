<script lang="ts">
	/**
	 * AIErrorFallback component for handling AI recognition errors.
	 * Req 2.7: On failure, show error and offer manual entry
	 * Req 2.10: On zero items, offer retry or manual entry
	 * D-DES-013: Show Try Again and Enter Manually buttons on timeout
	 */

	type ErrorType = 'timeout' | 'no_items' | 'ai_failure' | 'generic';

	interface Props {
		errorType: ErrorType;
		errorMessage: string;
		onRetry: () => void;
		onManualEntry: () => void;
		isRetrying?: boolean;
	}

	let { errorType, errorMessage, onRetry, onManualEntry, isRetrying = false }: Props = $props();

	/**
	 * Get title based on error type.
	 */
	function getTitle(): string {
		switch (errorType) {
			case 'timeout':
				return 'Recognition Timed Out';
			case 'no_items':
				return 'No Food Recognised';
			case 'ai_failure':
				return 'Recognition Unavailable';
			default:
				return 'Recognition Failed';
		}
	}

	/**
	 * Get icon based on error type.
	 */
	function getIcon(): string {
		switch (errorType) {
			case 'timeout':
				return '⏱️';
			case 'no_items':
				return '🔍';
			case 'ai_failure':
				return '⚠️';
			default:
				return '❌';
		}
	}
</script>

<div class="flex flex-col items-center gap-4 text-center">
	<!-- Error icon and title -->
	<div class="text-4xl">{getIcon()}</div>
	<h2 class="text-xl font-semibold">{getTitle()}</h2>

	<!-- Error message -->
	<p class="text-white/70 max-w-sm">
		{errorMessage}
	</p>

	<!-- Action buttons per D-DES-013 -->
	<div class="flex flex-col gap-2 w-full mt-2">
		<button
			onclick={onRetry}
			disabled={isRetrying}
			class="w-full rounded-lg bg-brand-accent py-4 text-lg font-semibold text-black min-h-[44px] disabled:opacity-50 disabled:cursor-not-allowed"
		>
			{#if isRetrying}
				Trying Again...
			{:else}
				Try Again
			{/if}
		</button>
		<button
			onclick={onManualEntry}
			disabled={isRetrying}
			class="w-full rounded-lg bg-white/10 py-4 text-lg font-semibold text-white min-h-[44px] disabled:opacity-50 disabled:cursor-not-allowed"
		>
			Enter Manually
		</button>
	</div>
</div>
