/**
 * Client-side preset API service.
 * Handles API calls to preset endpoints.
 * Req 6.1-6.8
 */
import type { Preset, CreatePresetInput, UpdatePresetInput } from '$lib/types/index.js';

/**
 * API response wrapper.
 */
interface ApiResponse<T> {
	data: T;
}

/**
 * API error response.
 */
interface ApiError {
	message: string;
}

/**
 * Create a new preset.
 * POST /api/presets
 * Req 6.1: Allow saving any meal as a named preset
 */
export async function createPreset(input: CreatePresetInput): Promise<Preset> {
	const response = await fetch('/api/presets', {
		method: 'POST',
		headers: {
			'Content-Type': 'application/json'
		},
		body: JSON.stringify(input)
	});

	if (!response.ok) {
		const error: ApiError = await response.json();
		throw new Error(error.message || 'Failed to create preset');
	}

	const { data }: ApiResponse<Preset> = await response.json();
	return data;
}

/**
 * Get all presets.
 * GET /api/presets
 * Req 6.3: List all presets
 */
export async function getPresets(): Promise<Preset[]> {
	const response = await fetch('/api/presets');

	if (!response.ok) {
		const error: ApiError = await response.json();
		throw new Error(error.message || 'Failed to get presets');
	}

	const { data }: ApiResponse<Preset[]> = await response.json();
	return data;
}

/**
 * Get a preset by ID.
 * GET /api/presets/[id]
 */
export async function getPresetById(id: string): Promise<Preset | null> {
	const response = await fetch(`/api/presets/${id}`);

	if (response.status === 404) {
		return null;
	}

	if (!response.ok) {
		const error: ApiError = await response.json();
		throw new Error(error.message || 'Failed to get preset');
	}

	const { data }: ApiResponse<Preset> = await response.json();
	return data;
}

/**
 * Update an existing preset.
 * PUT /api/presets/[id]
 * Req 6.6: Edit preset details after creation
 */
export async function updatePreset(id: string, updates: UpdatePresetInput): Promise<Preset> {
	const response = await fetch(`/api/presets/${id}`, {
		method: 'PUT',
		headers: {
			'Content-Type': 'application/json'
		},
		body: JSON.stringify(updates)
	});

	if (!response.ok) {
		const error: ApiError = await response.json();
		throw new Error(error.message || 'Failed to update preset');
	}

	const { data }: ApiResponse<Preset> = await response.json();
	return data;
}

/**
 * Delete a preset.
 * DELETE /api/presets/[id]
 * Req 6.7: Delete presets
 */
export async function deletePreset(id: string): Promise<void> {
	const response = await fetch(`/api/presets/${id}`, {
		method: 'DELETE'
	});

	if (!response.ok) {
		const error: ApiError = await response.json();
		throw new Error(error.message || 'Failed to delete preset');
	}
}
