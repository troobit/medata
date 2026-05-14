/**
 * Toast store for managing global toast notifications.
 * Uses Svelte 5 runes for reactive state management.
 */

export type ToastType = 'success' | 'error' | 'info';

export interface ToastMessage {
	id: string;
	message: string;
	type: ToastType;
	duration: number;
}

function createToastStore() {
	let toasts = $state<ToastMessage[]>([]);

	function generateId(): string {
		return Math.random().toString(36).slice(2, 11);
	}

	function show(message: string, type: ToastType = 'success', duration = 3000) {
		const id = generateId();
		toasts = [...toasts, { id, message, type, duration }];
		return id;
	}

	function dismiss(id: string) {
		toasts = toasts.filter((t) => t.id !== id);
	}

	function success(message: string, duration = 3000) {
		return show(message, 'success', duration);
	}

	function error(message: string, duration = 5000) {
		return show(message, 'error', duration);
	}

	function info(message: string, duration = 3000) {
		return show(message, 'info', duration);
	}

	return {
		get toasts() {
			return toasts;
		},
		show,
		dismiss,
		success,
		error,
		info
	};
}

export const toastStore = createToastStore();
