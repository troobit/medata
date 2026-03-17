/**
 * Cosmos DB implementation of IMealRepository.
 * Per design section 4.2.
 */
import { CosmosClient, type Container, type Database } from '@azure/cosmos';
import type { IMealRepository } from './meal-repository.js';
import type { Meal, CreateMealInput, UpdateMealInput } from '$lib/types/index.js';
import { PRIMARY_CONNECTION_STRING } from '$env/static/private';

const DATABASE_NAME = 'medata';
const CONTAINER_NAME = 'meals';

/**
 * Format a date as YYYY-MM-DD for partition key.
 * Per design D-DES-007: Day-based pagination.
 */
function formatPartitionKey(timestamp: number): string {
	const date = new Date(timestamp);
	const parts = date.toISOString().split('T');
	return parts[0] ?? '';
}

/**
 * Generate a UUID v4.
 */
function generateId(): string {
	return crypto.randomUUID();
}

/**
 * Cosmos DB document structure.
 * Includes partitionKey for efficient day-based queries.
 */
interface MealDocument {
	id: string;
	partitionKey: string;
	timestamp: number;
	items: Meal['items'];
	totalCarbs: number;
	totalProtein: number;
	totalFat: number;
	source: Meal['source'];
	imageUrl?: string;
	confidence?: number;
	createdAt: number;
	updatedAt: number;
}

/**
 * Cosmos DB implementation of the meal repository.
 */
export class CosmosMealRepository implements IMealRepository {
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

		// Create container with partition key
		const { container } = await this.database.containers.createIfNotExists({
			id: CONTAINER_NAME,
			partitionKey: { paths: ['/partitionKey'] }
		});
		this.container = container;
		this.initialised = true;

		return this.container;
	}

	async create(input: CreateMealInput): Promise<Meal> {
		const container = await this.ensureInitialised();

		const now = Date.now();
		const id = generateId();
		const partitionKey = formatPartitionKey(input.timestamp);

		const document: MealDocument = {
			id,
			partitionKey,
			timestamp: input.timestamp,
			items: input.items,
			totalCarbs: input.totalCarbs,
			totalProtein: input.totalProtein,
			totalFat: input.totalFat,
			source: input.source,
			createdAt: now,
			updatedAt: now
		};

		// Only add optional fields if they exist
		if (input.imageUrl !== undefined) {
			document.imageUrl = input.imageUrl;
		}
		if (input.confidence !== undefined) {
			document.confidence = input.confidence;
		}

		const { resource } = await container.items.create(document);

		if (!resource) {
			throw new Error('Failed to create meal');
		}

		return this.documentToMeal(resource);
	}

	async getById(id: string): Promise<Meal | null> {
		const container = await this.ensureInitialised();

		// Since we don't know the partition key, we need to query across partitions
		const querySpec = {
			query: 'SELECT * FROM c WHERE c.id = @id',
			parameters: [{ name: '@id', value: id }]
		};

		const { resources } = await container.items.query<MealDocument>(querySpec).fetchAll();

		if (resources.length === 0) {
			return null;
		}

		const doc = resources[0];
		if (!doc) {
			return null;
		}

		return this.documentToMeal(doc);
	}

	async getByDay(date: Date): Promise<Meal[]> {
		const container = await this.ensureInitialised();

		const parts = date.toISOString().split('T');
		const partitionKey = parts[0] ?? '';

		// Query within a single partition (efficient)
		const querySpec = {
			query: 'SELECT * FROM c WHERE c.partitionKey = @partitionKey ORDER BY c.timestamp DESC',
			parameters: [{ name: '@partitionKey', value: partitionKey }]
		};

		const { resources } = await container.items
			.query<MealDocument>(querySpec, {
				partitionKey
			})
			.fetchAll();

		return resources.map((doc) => this.documentToMeal(doc));
	}

	async getByDateRange(start: Date, end: Date): Promise<Meal[]> {
		const container = await this.ensureInitialised();

		// Convert dates to timestamps for range query
		const startTimestamp = start.setHours(0, 0, 0, 0);
		const endTimestamp = end.setHours(23, 59, 59, 999);

		// Cross-partition query for date range
		const querySpec = {
			query:
				'SELECT * FROM c WHERE c.timestamp >= @start AND c.timestamp <= @end ORDER BY c.timestamp DESC',
			parameters: [
				{ name: '@start', value: startTimestamp },
				{ name: '@end', value: endTimestamp }
			]
		};

		const { resources } = await container.items.query<MealDocument>(querySpec).fetchAll();

		return resources.map((doc) => this.documentToMeal(doc));
	}

	async update(id: string, updates: UpdateMealInput): Promise<Meal> {
		const container = await this.ensureInitialised();

		// First, find the existing meal to get its partition key
		const existing = await this.getById(id);
		if (!existing) {
			throw new Error(`Meal with id ${id} not found`);
		}

		const partitionKey = formatPartitionKey(existing.timestamp);

		// Read the full document
		const { resource: document } = await container.item(id, partitionKey).read<MealDocument>();

		if (!document) {
			throw new Error(`Meal with id ${id} not found`);
		}

		// Apply updates
		const updatedDocument: MealDocument = {
			...document,
			updatedAt: Date.now()
		};

		if (updates.timestamp !== undefined) {
			updatedDocument.timestamp = updates.timestamp;
		}
		if (updates.items !== undefined) {
			updatedDocument.items = updates.items;
		}
		if (updates.totalCarbs !== undefined) {
			updatedDocument.totalCarbs = updates.totalCarbs;
		}
		if (updates.totalProtein !== undefined) {
			updatedDocument.totalProtein = updates.totalProtein;
		}
		if (updates.totalFat !== undefined) {
			updatedDocument.totalFat = updates.totalFat;
		}
		if (updates.imageUrl !== undefined) {
			updatedDocument.imageUrl = updates.imageUrl;
		}

		// If timestamp changed, partition key might change too
		if (updates.timestamp !== undefined && updates.timestamp !== document.timestamp) {
			updatedDocument.partitionKey = formatPartitionKey(updates.timestamp);

			// Delete from old partition and create in new partition
			await container.item(id, partitionKey).delete();
			const { resource } = await container.items.create(updatedDocument);

			if (!resource) {
				throw new Error('Failed to update meal');
			}
			return this.documentToMeal(resource);
		}

		// Replace in same partition
		const { resource } = await container.item(id, partitionKey).replace(updatedDocument);

		if (!resource) {
			throw new Error('Failed to update meal');
		}

		return this.documentToMeal(resource);
	}

	async delete(id: string): Promise<void> {
		const container = await this.ensureInitialised();

		// Find the meal to get its partition key
		const existing = await this.getById(id);
		if (!existing) {
			throw new Error(`Meal with id ${id} not found`);
		}

		const partitionKey = formatPartitionKey(existing.timestamp);

		await container.item(id, partitionKey).delete();
	}

	/**
	 * Convert Cosmos document to Meal type.
	 * Strips out Cosmos-specific fields.
	 */
	private documentToMeal(doc: MealDocument): Meal {
		const meal: Meal = {
			id: doc.id,
			timestamp: doc.timestamp,
			items: doc.items,
			totalCarbs: doc.totalCarbs,
			totalProtein: doc.totalProtein,
			totalFat: doc.totalFat,
			source: doc.source,
			createdAt: doc.createdAt,
			updatedAt: doc.updatedAt
		};

		if (doc.imageUrl !== undefined) {
			meal.imageUrl = doc.imageUrl;
		}
		if (doc.confidence !== undefined) {
			meal.confidence = doc.confidence;
		}

		return meal;
	}
}

/**
 * Singleton instance for the meal repository.
 */
let mealRepository: CosmosMealRepository | null = null;

/**
 * Get the meal repository instance.
 * Creates a new instance if one doesn't exist.
 */
export function getMealRepository(): IMealRepository {
	if (!mealRepository) {
		mealRepository = new CosmosMealRepository();
	}
	return mealRepository;
}
