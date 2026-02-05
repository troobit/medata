/**
 * POST/GET /api/presets endpoint
 * Per design section 3.3
 * Create a new preset or list all presets
 */
import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { CreatePresetInputSchema } from '$lib/schemas/index.js';
import { getPresetRepository } from '$lib/repositories/index.js';
import type { CreatePresetInput } from '$lib/types/index.js';

/**
 * POST /api/presets
 * Create a new preset
 * Req 6.1: Allow saving any meal as a named preset
 * Req 6.2: Store name, category, items, and totals
 */
export const POST: RequestHandler = async ({ request }) => {
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
	const parseResult = CreatePresetInputSchema.safeParse(body);
	if (!parseResult.success) {
		const firstError = parseResult.error.issues[0];
		return error(400, {
			message: `${firstError?.path.join('.') || 'Input'} is invalid. ${firstError?.message || ''}`
		});
	}

	// Build the preset input
	const data = parseResult.data;
	const presetInput: CreatePresetInput = {
		name: data.name,
		category: data.category,
		items: data.items
	};

	// Create the preset
	try {
		const presetRepository = getPresetRepository();
		const preset = await presetRepository.create(presetInput);

		return json(
			{
				data: preset
			},
			{ status: 201 }
		);
	} catch (e) {
		console.error('Preset creation error:', e);
		return error(500, {
			message: 'Save failed. Try again.'
		});
	}
};

/**
 * GET /api/presets
 * List all presets
 * Req 6.3: List all presets
 */
export const GET: RequestHandler = async () => {
	try {
		const presetRepository = getPresetRepository();
		const presets = await presetRepository.getAll();

		return json({
			data: presets
		});
	} catch (e) {
		console.error('Get presets error:', e);
		return error(500, {
			message: 'Failed to retrieve presets. Try again.'
		});
	}
};
