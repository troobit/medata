/**
 * Cosmos DB implementation of IPresetRepository.
 * Per design section 4.2.
 * Uses /category partition key for efficient category-based queries.
 */
import { CosmosClient, type Container, type Database } from '@azure/cosmos';
import type { IPresetRepository } from './preset-repository.js';
import type { Preset, CreatePresetInput, UpdatePresetInput, PresetCategory } from '$lib/types/index.js';
import { sumMacros } from '$lib/utils/index.js';
import { PRIMARY_CONNECTION_STRING } from '$env/static/private';

const DATABASE_NAME = 'medata';
const CONTAINER_NAME = 'presets';

/**
 * Generate a UUID v4.
 */
function generateId(): string {
	return crypto.randomUUID();
}

/**
 * Cosmos DB document structure for presets.
 * Uses category as partition key for efficient category-based queries.
 */
interface PresetDocument {
	id: string;
	name: string;
	category: PresetCategory;
	items: Preset['items'];
	totalCarbs: number;
	totalProtein: number;
	totalFat: number;
	createdAt: number;
	updatedAt: number;
}

/**
 * Cosmos DB implementation of the preset repository.
 */
export class CosmosPresetRepository implements IPresetRepository {
	private client: CosmosClient;
	private database: Database | null = null;
	private container: Container | null = null;
	private initialised = false;

	constructor(connectionString?: string) {
		const connStr = connectionString ?? PRIMARY_CONNECTION_STRING;
		if (!connStr) {
			throw new Error('PRIMARY_CONNECTION_STRING environment variable is not set');
		}
		this.client = new CosmosClient(connStr);
	}

	/**
	 * Ensure database and container exist.
	 * Creates them if they don't exist.
	 */
	private async ensureInitialised(): Promise<Container> {
		if (this.initialised && this.container) {
			return this.container;
		}

		// Create database if not exists
		const { database } = await this.client.databases.createIfNotExists({
			id: DATABASE_NAME
		});
		this.database = database;

		// Create container with category as partition key
		const { container } = await this.database.containers.createIfNotExists({
			id: CONTAINER_NAME,
			partitionKey: { paths: ['/category'] }
		});
		this.container = container;
		this.initialised = true;

		return this.container;
	}

	async create(input: CreatePresetInput): Promise<Preset> {
		const container = await this.ensureInitialised();

		const now = Date.now();
		const id = generateId();

		// Calculate totals from items
		const totals = sumMacros(input.items);

		const document: PresetDocument = {
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

		const { resource } = await container.items.create(document);

		if (!resource) {
			throw new Error('Failed to create preset');
		}

		return this.documentToPreset(resource);
	}

	async getById(id: string): Promise<Preset | null> {
		const container = await this.ensureInitialised();

		// Since we don't know the category (partition key), we need to query across partitions
		const querySpec = {
			query: 'SELECT * FROM c WHERE c.id = @id',
			parameters: [{ name: '@id', value: id }]
		};

		const { resources } = await container.items.query<PresetDocument>(querySpec).fetchAll();

		if (resources.length === 0) {
			return null;
		}

		const doc = resources[0];
		if (!doc) {
			return null;
		}

		return this.documentToPreset(doc);
	}

	async getAll(): Promise<Preset[]> {
		const container = await this.ensureInitialised();

		// Cross-partition query to get all presets
		const querySpec = {
			query: 'SELECT * FROM c ORDER BY c.name'
		};

		const { resources } = await container.items.query<PresetDocument>(querySpec).fetchAll();

		return resources.map((doc) => this.documentToPreset(doc));
	}

	async getByCategory(category: PresetCategory): Promise<Preset[]> {
		const container = await this.ensureInitialised();

		// Query within a single partition (efficient)
		const querySpec = {
			query: 'SELECT * FROM c WHERE c.category = @category ORDER BY c.name',
			parameters: [{ name: '@category', value: category }]
		};

		const { resources } = await container.items
			.query<PresetDocument>(querySpec, {
				partitionKey: category
			})
			.fetchAll();

		return resources.map((doc) => this.documentToPreset(doc));
	}

	async update(id: string, updates: UpdatePresetInput): Promise<Preset> {
		const container = await this.ensureInitialised();

		// First, find the existing preset to get its category (partition key)
		const existing = await this.getById(id);
		if (!existing) {
			throw new Error(`Preset with id ${id} not found`);
		}

		const oldCategory = existing.category;

		// Read the full document
		const { resource: document } = await container.item(id, oldCategory).read<PresetDocument>();

		if (!document) {
			throw new Error(`Preset with id ${id} not found`);
		}

		// Apply updates
		const updatedDocument: PresetDocument = {
			...document,
			updatedAt: Date.now()
		};

		if (updates.name !== undefined) {
			updatedDocument.name = updates.name;
		}
		if (updates.category !== undefined) {
			updatedDocument.category = updates.category;
		}
		if (updates.items !== undefined) {
			updatedDocument.items = updates.items;
			// Recalculate totals when items change
			const totals = sumMacros(updates.items);
			updatedDocument.totalCarbs = totals.carbs;
			updatedDocument.totalProtein = totals.protein;
			updatedDocument.totalFat = totals.fat;
		}

		// If category changed, partition key changes too
		if (updates.category !== undefined && updates.category !== oldCategory) {
			// Delete from old partition and create in new partition
			await container.item(id, oldCategory).delete();
			const { resource } = await container.items.create(updatedDocument);

			if (!resource) {
				throw new Error('Failed to update preset');
			}
			return this.documentToPreset(resource);
		}

		// Replace in same partition
		const { resource } = await container.item(id, oldCategory).replace(updatedDocument);

		if (!resource) {
			throw new Error('Failed to update preset');
		}

		return this.documentToPreset(resource);
	}

	async delete(id: string): Promise<void> {
		const container = await this.ensureInitialised();

		// Find the preset to get its category (partition key)
		const existing = await this.getById(id);
		if (!existing) {
			throw new Error(`Preset with id ${id} not found`);
		}

		await container.item(id, existing.category).delete();
	}

	/**
	 * Convert Cosmos document to Preset type.
	 * Strips out Cosmos-specific fields.
	 */
	private documentToPreset(doc: PresetDocument): Preset {
		return {
			id: doc.id,
			name: doc.name,
			category: doc.category,
			items: doc.items,
			totalCarbs: doc.totalCarbs,
			totalProtein: doc.totalProtein,
			totalFat: doc.totalFat,
			createdAt: doc.createdAt,
			updatedAt: doc.updatedAt
		};
	}
}

/**
 * Singleton instance for the preset repository.
 */
let presetRepository: CosmosPresetRepository | null = null;

/**
 * Get the preset repository instance.
 * Creates a new instance if one doesn't exist.
 */
export function getPresetRepository(): IPresetRepository {
	if (!presetRepository) {
		presetRepository = new CosmosPresetRepository();
	}
	return presetRepository;
}
