/**
 * GET/PUT/DELETE /api/presets/[id] endpoint
 * Per design section 3.3
 * Get, update, or delete a preset by ID
 */
import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { UpdatePresetInputSchema } from '$lib/schemas/index.js';
import { getPresetRepository } from '$lib/repositories/index.js';
import type { UpdatePresetInput } from '$lib/types/index.js';

/**
 * GET /api/presets/[id]
 * Get a preset by ID
 */
export const GET: RequestHandler = async ({ params }) => {
	const { id } = params;

	try {
		const presetRepository = getPresetRepository();
		const preset = await presetRepository.getById(id);

		if (!preset) {
			return error(404, {
				message: 'Preset not found.'
			});
		}

		return json({
			data: preset
		});
	} catch (e) {
		console.error('Get preset error:', e);
		return error(500, {
			message: 'Failed to retrieve preset. Try again.'
		});
	}
};

/**
 * PUT /api/presets/[id]
 * Update a preset
 * Req 6.6: Edit preset details after creation
 */
export const PUT: RequestHandler = async ({ params, request }) => {
	const { id } = params;

	// Parse request body
	let body: unknown;
	try {
		body = await request.json();
	} catch {
		return error(400, {
			message: 'Invalid JSON in request body.'
		});
	}

	// Validate input
	const parseResult = UpdatePresetInputSchema.safeParse(body);
	if (!parseResult.success) {
		const firstError = parseResult.error.issues[0];
		return error(400, {
			message: `${firstError?.path.join('.') || 'Input'} is invalid. ${firstError?.message || ''}`
		});
	}

	// Build update input explicitly to handle optional fields
	const data = parseResult.data;
	const updates: UpdatePresetInput = {};

	if (data.name !== undefined) {
		updates.name = data.name;
	}
	if (data.category !== undefined) {
		updates.category = data.category;
	}
	if (data.items !== undefined) {
		updates.items = data.items;
	}

	// Update the preset
	try {
		const presetRepository = getPresetRepository();
		const preset = await presetRepository.update(id, updates);

		return json({
			data: preset
		});
	} catch (e) {
		if (e instanceof Error && e.message.includes('not found')) {
			return error(404, {
				message: 'Preset not found.'
			});
		}
		console.error('Update preset error:', e);
		return error(500, {
			message: 'Update failed. Try again.'
		});
	}
};

/**
 * DELETE /api/presets/[id]
 * Delete a preset
 * Req 6.7: Delete presets
 */
export const DELETE: RequestHandler = async ({ params }) => {
	const { id } = params;

	try {
		const presetRepository = getPresetRepository();
		await presetRepository.delete(id);

		return json({
			data: { success: true }
		});
	} catch (e) {
		if (e instanceof Error && e.message.includes('not found')) {
			return error(404, {
				message: 'Preset not found.'
			});
		}
		console.error('Delete preset error:', e);
		return error(500, {
			message: 'Delete failed. Try again.'
		});
	}
};
