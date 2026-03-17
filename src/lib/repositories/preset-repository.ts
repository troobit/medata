/**
 * Preset repository interface.
 * Per design section 3.3.
 * Req 6.1-6.8
 */
import type { Preset, CreatePresetInput, UpdatePresetInput, PresetCategory } from '$lib/types/index.js';

/**
 * Interface for preset data persistence.
 * Implements repository pattern for data access abstraction.
 */
export interface IPresetRepository {
	/**
	 * Create a new preset.
	 * Req 6.1: Allow saving any meal as a named preset (including emoji-only names).
	 * Req 6.2: Store name, category, items, and totals.
	 *
	 * @param preset - The preset data to create
	 * @returns The created preset with generated id and timestamps
	 */
	create(preset: CreatePresetInput): Promise<Preset>;

	/**
	 * Get a preset by its ID.
	 *
	 * @param id - The preset ID
	 * @returns The preset if found, null otherwise
	 */
	getById(id: string): Promise<Preset | null>;

	/**
	 * Get all presets.
	 * Req 6.3: List all presets.
	 *
	 * @returns Array of all presets, sorted by name
	 */
	getAll(): Promise<Preset[]>;

	/**
	 * Get presets by category.
	 * Per design section 3.3: Group by category (meal/snack).
	 *
	 * @param category - The category to filter by
	 * @returns Array of presets in that category, sorted by name
	 */
	getByCategory(category: PresetCategory): Promise<Preset[]>;

	/**
	 * Update an existing preset.
	 * Req 6.6: Edit preset details after creation.
	 *
	 * @param id - The preset ID to update
	 * @param updates - The fields to update
	 * @returns The updated preset
	 * @throws Error if preset not found
	 */
	update(id: string, updates: UpdatePresetInput): Promise<Preset>;

	/**
	 * Delete a preset.
	 * Req 6.7: Delete presets.
	 *
	 * @param id - The preset ID to delete
	 * @throws Error if preset not found
	 */
	delete(id: string): Promise<void>;
}
