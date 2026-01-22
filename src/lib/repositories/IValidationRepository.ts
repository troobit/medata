import type {
  TestDatasetEntry,
  CreateTestDataInput,
  UpdateTestDataInput,
  ValidationResult,
  CorrectionHistoryEntry,
  FoodCategory,
  GroundTruthSource
} from '$lib/types';

/**
 * Repository interface for validation data operations
 */
export interface IValidationRepository {
  // Test Dataset Operations
  createTestEntry(input: CreateTestDataInput): Promise<TestDatasetEntry>;
  getTestEntryById(id: string): Promise<TestDatasetEntry | null>;
  updateTestEntry(id: string, updates: UpdateTestDataInput): Promise<TestDatasetEntry>;
  deleteTestEntry(id: string): Promise<void>;
  getAllTestEntries(): Promise<TestDatasetEntry[]>;
  getTestEntriesByCategory(category: FoodCategory): Promise<TestDatasetEntry[]>;
  getTestEntriesBySource(source: GroundTruthSource): Promise<TestDatasetEntry[]>;
  bulkImportTestEntries(entries: TestDatasetEntry[]): Promise<void>;
  clearTestDataset(): Promise<void>;

  // Validation Results Operations
  saveValidationResult(result: ValidationResult): Promise<void>;
  getValidationResults(testEntryId: string): Promise<ValidationResult[]>;
  getValidationResultsByProvider(provider: string): Promise<ValidationResult[]>;
  getAllValidationResults(): Promise<ValidationResult[]>;
  clearValidationResults(): Promise<void>;

  // Correction History Operations
  saveCorrectionHistory(entry: CorrectionHistoryEntry): Promise<void>;
  getCorrectionHistoryByEvent(eventId: string): Promise<CorrectionHistoryEntry | null>;
  getCorrectionHistoryByProvider(provider: string): Promise<CorrectionHistoryEntry[]>;
  getCorrectionHistoryByCategory(category: FoodCategory): Promise<CorrectionHistoryEntry[]>;
  getAllCorrectionHistory(): Promise<CorrectionHistoryEntry[]>;
  clearCorrectionHistory(): Promise<void>;
}
