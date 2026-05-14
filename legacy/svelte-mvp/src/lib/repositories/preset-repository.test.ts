/**
 * Integration tests for preset repository.
 * Per design section 6.4
 * Task 55: Test preset CRUD operations
 */
import { describe, it, expect, beforeEach } from 'vitest';
import type { IPresetRepository } from './preset-repository.js';
import type { Preset, CreatePresetInput, UpdatePresetInput, PresetCategory } from '$lib/types/index.js';
import { sumMacros } from '$lib/utils/index.js';

/**
 * In-memory implementation for testing.
 * Matches the IPresetRepository interface.
 */
class InMemoryPresetRepository implements IPresetRepository {
	private presets: Map<string, Preset> = new Map();
	private idCounter = 0;

	async create(input: CreatePresetInput): Promise<Preset> {
		const id = `test-preset-${++this.idCounter}`;
		const now = Date.now();

		// Calculate totals from items
		const totals = sumMacros(input.items);

		const preset: Preset = {
			id,
			name: input.name,
			category: input.category,
			items: input.items,
			totalCarbs: totals.carbs,
			totalProtein: totals.protein,
			totalFat: totals.fat,
			createdAt: now,
			updatedAt: now
		};

		this.presets.set(id, preset);
		return preset;
	}

	async getById(id: string): Promise<Preset | null> {
		return this.presets.get(id) ?? null;
	}

	async getAll(): Promise<Preset[]> {
		return Array.from(this.presets.values()).sort((a, b) => a.name.localeCompare(b.name));
	}

	async getByCategory(category: PresetCategory): Promise<Preset[]> {
		return Array.from(this.presets.values())
			.filter((preset) => preset.category === category)
			.sort((a, b) => a.name.localeCompare(b.name));
	}

	async update(id: string, updates: UpdatePresetInput): Promise<Preset> {
		const existing = this.presets.get(id);
		if (!existing) {
			throw new Error(`Preset with id ${id} not found`);
		}

		const updated: Preset = {
			...existing,
			updatedAt: Date.now()
		};

		if (updates.name !== undefined) {
			updated.name = updates.name;
		}
		if (updates.category !== undefined) {
			updated.category = updates.category;
		}
		if (updates.items !== undefined) {
			updated.items = updates.items;
			// Recalculate totals when items change
			const totals = sumMacros(updates.items);
			updated.totalCarbs = totals.carbs;
			updated.totalProtein = totals.protein;
			updated.totalFat = totals.fat;
		}

		this.presets.set(id, updated);
		return updated;
	}

	async delete(id: string): Promise<void> {
		if (!this.presets.has(id)) {
			throw new Error(`Preset with id ${id} not found`);
		}
		this.presets.delete(id);
	}

	// Helper for tests
	clear() {
		this.presets.clear();
		this.idCounter = 0;
	}
}

describe('IPresetRepository', () => {
	let repository: InMemoryPresetRepository;

	beforeEach(() => {
		repository = new InMemoryPresetRepository();
	});

	const createTestPresetInput = (overrides: Partial<CreatePresetInput> = {}): CreatePresetInput => ({
		name: 'Test Preset',
		category: 'meal',
		items: [{ name: 'Test Food', carbs: 10, protein: 5, fat: 3 }],
		...overrides
	});

	describe('create', () => {
		it('creates a preset and returns it with generated id', async () => {
			const input = createTestPresetInput();

			const preset = await repository.create(input);

			expect(preset.id).toBeDefined();
			expect(preset.name).toBe(input.name);
			expect(preset.category).toBe(input.category);
			expect(preset.items).toEqual(input.items);
		});

		it('calculates totals from items', async () => {
			const input = createTestPresetInput({
				items: [
					{ name: 'Food 1', carbs: 10, protein: 5, fat: 3 },
					{ name: 'Food 2', carbs: 20, protein: 10, fat: 6 }
				]
			});

			const preset = await repository.create(input);

			expect(preset.totalCarbs).toBe(30);
			expect(preset.totalProtein).toBe(15);
			expect(preset.totalFat).toBe(9);
		});

		it('sets createdAt and updatedAt timestamps', async () => {
			const beforeCreate = Date.now();
			const preset = await repository.create(createTestPresetInput());
			const afterCreate = Date.now();

			expect(preset.createdAt).toBeGreaterThanOrEqual(beforeCreate);
			expect(preset.createdAt).toBeLessThanOrEqual(afterCreate);
			expect(preset.updatedAt).toBe(preset.createdAt);
		});

		it('allows emoji-only names', async () => {
			const input = createTestPresetInput({ name: '🍕🍔' });

			const preset = await repository.create(input);

			expect(preset.name).toBe('🍕🍔');
		});

		it('creates preset with snack category', async () => {
			const input = createTestPresetInput({ category: 'snack' });

			const preset = await repository.create(input);

			expect(preset.category).toBe('snack');
		});
	});

	describe('getById', () => {
		it('returns preset when found', async () => {
			const created = await repository.create(createTestPresetInput());

			const found = await repository.getById(created.id);

			expect(found).toEqual(created);
		});

		it('returns null when not found', async () => {
			const found = await repository.getById('non-existent-id');

			expect(found).toBeNull();
		});
	});

	describe('getAll', () => {
		it('returns all presets sorted by name', async () => {
			await repository.create(createTestPresetInput({ name: 'Zebra' }));
			await repository.create(createTestPresetInput({ name: 'Apple' }));
			await repository.create(createTestPresetInput({ name: 'Mango' }));

			const presets = await repository.getAll();

			expect(presets).toHaveLength(3);
			expect(presets[0]!.name).toBe('Apple');
			expect(presets[1]!.name).toBe('Mango');
			expect(presets[2]!.name).toBe('Zebra');
		});

		it('returns empty array when no presets', async () => {
			const presets = await repository.getAll();

			expect(presets).toHaveLength(0);
		});
	});

	describe('getByCategory', () => {
		it('returns presets for the specified category', async () => {
			await repository.create(createTestPresetInput({ name: 'Breakfast', category: 'meal' }));
			await repository.create(createTestPresetInput({ name: 'Chips', category: 'snack' }));
			await repository.create(createTestPresetInput({ name: 'Lunch', category: 'meal' }));

			const meals = await repository.getByCategory('meal');
			const snacks = await repository.getByCategory('snack');

			expect(meals).toHaveLength(2);
			expect(snacks).toHaveLength(1);
			expect(snacks[0]!.name).toBe('Chips');
		});

		it('returns presets sorted by name within category', async () => {
			await repository.create(createTestPresetInput({ name: 'Lunch', category: 'meal' }));
			await repository.create(createTestPresetInput({ name: 'Breakfast', category: 'meal' }));

			const meals = await repository.getByCategory('meal');

			expect(meals[0]!.name).toBe('Breakfast');
			expect(meals[1]!.name).toBe('Lunch');
		});

		it('returns empty array when no presets in category', async () => {
			await repository.create(createTestPresetInput({ category: 'meal' }));

			const snacks = await repository.getByCategory('snack');

			expect(snacks).toHaveLength(0);
		});
	});

	describe('update', () => {
		it('updates preset name and returns updated version', async () => {
			const created = await repository.create(createTestPresetInput());

			const updated = await repository.update(created.id, { name: 'Updated Name' });

			expect(updated.name).toBe('Updated Name');
		});

		it('updates preset category', async () => {
			const created = await repository.create(createTestPresetInput({ category: 'meal' }));

			const updated = await repository.update(created.id, { category: 'snack' });

			expect(updated.category).toBe('snack');
		});

		it('updates items and recalculates totals', async () => {
			const created = await repository.create(createTestPresetInput());

			const updated = await repository.update(created.id, {
				items: [
					{ name: 'New Food 1', carbs: 50, protein: 20, fat: 10 },
					{ name: 'New Food 2', carbs: 30, protein: 15, fat: 8 }
				]
			});

			expect(updated.items).toHaveLength(2);
			expect(updated.totalCarbs).toBe(80);
			expect(updated.totalProtein).toBe(35);
			expect(updated.totalFat).toBe(18);
		});

		it('updates updatedAt timestamp', async () => {
			const created = await repository.create(createTestPresetInput());

			// Wait a bit to ensure different timestamp
			await new Promise((resolve) => setTimeout(resolve, 10));

			const updated = await repository.update(created.id, { name: 'New Name' });

			expect(updated.updatedAt).toBeGreaterThan(created.updatedAt);
		});

		it('preserves unchanged fields', async () => {
			const input = createTestPresetInput({
				name: 'Original Name',
				category: 'meal',
				items: [{ name: 'Food', carbs: 10, protein: 5, fat: 3 }]
			});
			const created = await repository.create(input);

			const updated = await repository.update(created.id, { name: 'New Name' });

			expect(updated.category).toBe('meal');
			expect(updated.items).toEqual(input.items);
			expect(updated.totalCarbs).toBe(10);
		});

		it('throws error when preset not found', async () => {
			await expect(repository.update('non-existent-id', { name: 'New Name' })).rejects.toThrow(
				'not found'
			);
		});
	});

	describe('delete', () => {
		it('removes preset from storage', async () => {
			const created = await repository.create(createTestPresetInput());

			await repository.delete(created.id);

			const found = await repository.getById(created.id);
			expect(found).toBeNull();
		});

		it('throws error when preset not found', async () => {
			await expect(repository.delete('non-existent-id')).rejects.toThrow('not found');
		});
	});
});
