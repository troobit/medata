import { v4 as uuidv4 } from 'uuid';
import { getDb } from '$lib/db';
import type {
  TestDatasetEntry,
  CreateTestDataInput,
  UpdateTestDataInput,
  ValidationResult,
  CorrectionHistoryEntry,
  FoodCategory,
  GroundTruthSource
} from '$lib/types';
import type { IValidationRepository } from './IValidationRepository';

/**
 * IndexedDB implementation of the validation repository using Dexie.js
 */
export class IndexedDBValidationRepository implements IValidationRepository {
  private get db() {
    return getDb();
  }

  // Test Dataset Operations

  async createTestEntry(input: CreateTestDataInput): Promise<TestDatasetEntry> {
    const now = new Date();
    const entry: TestDatasetEntry = {
      ...input,
      id: uuidv4(),
      createdAt: now,
      updatedAt: now
    };

    await this.db.testDataset.add(entry);
    return entry;
  }

  async getTestEntryById(id: string): Promise<TestDatasetEntry | null> {
    const entry = await this.db.testDataset.get(id);
    return entry ?? null;
  }

  async updateTestEntry(id: string, updates: UpdateTestDataInput): Promise<TestDatasetEntry> {
    const existing = await this.getTestEntryById(id);
    if (!existing) {
      throw new Error(`Test entry with id ${id} not found`);
    }

    const updated: TestDatasetEntry = {
      ...existing,
      ...updates,
      updatedAt: new Date()
    };

    await this.db.testDataset.put(updated);
    return updated;
  }

  async deleteTestEntry(id: string): Promise<void> {
    await this.db.testDataset.delete(id);
  }

  async getAllTestEntries(): Promise<TestDatasetEntry[]> {
    return this.db.testDataset.orderBy('createdAt').reverse().toArray();
  }

  async getTestEntriesByCategory(category: FoodCategory): Promise<TestDatasetEntry[]> {
    return this.db.testDataset.where('category').equals(category).toArray();
  }

  async getTestEntriesBySource(source: GroundTruthSource): Promise<TestDatasetEntry[]> {
    return this.db.testDataset.where('source').equals(source).toArray();
  }

  async bulkImportTestEntries(entries: TestDatasetEntry[]): Promise<void> {
    await this.db.testDataset.bulkPut(entries);
  }

  async clearTestDataset(): Promise<void> {
    await this.db.testDataset.clear();
  }

  // Validation Results Operations

  async saveValidationResult(result: ValidationResult): Promise<void> {
    await this.db.validationResults.put(result);
  }

  async getValidationResults(testEntryId: string): Promise<ValidationResult[]> {
    return this.db.validationResults.where('testEntryId').equals(testEntryId).toArray();
  }

  async getValidationResultsByProvider(provider: string): Promise<ValidationResult[]> {
    return this.db.validationResults.where('aiProvider').equals(provider).toArray();
  }

  async getAllValidationResults(): Promise<ValidationResult[]> {
    return this.db.validationResults.toArray();
  }

  async clearValidationResults(): Promise<void> {
    await this.db.validationResults.clear();
  }

  // Correction History Operations

  async saveCorrectionHistory(entry: CorrectionHistoryEntry): Promise<void> {
    await this.db.correctionHistory.put(entry);
  }

  async getCorrectionHistoryByEvent(eventId: string): Promise<CorrectionHistoryEntry | null> {
    const entry = await this.db.correctionHistory.where('eventId').equals(eventId).first();
    return entry ?? null;
  }

  async getCorrectionHistoryByProvider(provider: string): Promise<CorrectionHistoryEntry[]> {
    return this.db.correctionHistory.where('aiProvider').equals(provider).toArray();
  }

  async getCorrectionHistoryByCategory(category: FoodCategory): Promise<CorrectionHistoryEntry[]> {
    return this.db.correctionHistory.where('category').equals(category).toArray();
  }

  async getAllCorrectionHistory(): Promise<CorrectionHistoryEntry[]> {
    return this.db.correctionHistory.orderBy('timestamp').reverse().toArray();
  }

  async clearCorrectionHistory(): Promise<void> {
    await this.db.correctionHistory.clear();
  }
}
