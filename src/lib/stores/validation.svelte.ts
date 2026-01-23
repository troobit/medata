import { getValidationService } from '$lib/services';
import type {
  TestDatasetEntry,
  CreateTestDataInput,
  UpdateTestDataInput,
  ValidationResult,
  CorrectionHistoryEntry,
  AccuracyMetrics,
  FoodCategory,
  GroundTruthSource,
  TestDatasetExport,
  USDAFoodEntry,
  DatasetImportResult,
  CorrectionPatternStats,
  PromptEnhancement,
  MacroData
} from '$lib/types';

/**
 * Reactive store for validation data using Svelte 5 runes
 */
function createValidationStore() {
  let testEntries = $state<TestDatasetEntry[]>([]);
  let validationResults = $state<ValidationResult[]>([]);
  let correctionHistory = $state<CorrectionHistoryEntry[]>([]);
  let accuracyMetrics = $state<AccuracyMetrics | null>(null);
  let correctionPatterns = $state<CorrectionPatternStats[]>([]);
  let promptEnhancements = $state<PromptEnhancement[]>([]);
  let loading = $state(false);
  let error = $state<string | null>(null);

  const service = getValidationService();

  // Test Dataset Operations

  async function loadTestEntries() {
    loading = true;
    error = null;
    try {
      testEntries = await service.getAllTestEntries();
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to load test entries';
    } finally {
      loading = false;
    }
  }

  async function loadTestEntriesByCategory(category: FoodCategory) {
    loading = true;
    error = null;
    try {
      testEntries = await service.getTestEntriesByCategory(category);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to load test entries';
    } finally {
      loading = false;
    }
  }

  async function loadTestEntriesBySource(source: GroundTruthSource) {
    loading = true;
    error = null;
    try {
      testEntries = await service.getTestEntriesBySource(source);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to load test entries';
    } finally {
      loading = false;
    }
  }

  async function createTestEntry(input: CreateTestDataInput) {
    loading = true;
    error = null;
    try {
      const entry = await service.createTestEntry(input);
      testEntries = [entry, ...testEntries];
      return entry;
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to create test entry';
      throw e;
    } finally {
      loading = false;
    }
  }

  async function updateTestEntry(id: string, updates: UpdateTestDataInput) {
    loading = true;
    error = null;
    try {
      const updated = await service.updateTestEntry(id, updates);
      testEntries = testEntries.map((e) => (e.id === id ? updated : e));
      return updated;
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to update test entry';
      throw e;
    } finally {
      loading = false;
    }
  }

  async function deleteTestEntry(id: string) {
    loading = true;
    error = null;
    try {
      await service.deleteTestEntry(id);
      testEntries = testEntries.filter((e) => e.id !== id);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to delete test entry';
      throw e;
    } finally {
      loading = false;
    }
  }

  // Validation Results Operations

  async function loadValidationResults() {
    loading = true;
    error = null;
    try {
      validationResults = await service.getAllValidationResults();
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to load validation results';
    } finally {
      loading = false;
    }
  }

  async function saveValidationResult(result: ValidationResult) {
    loading = true;
    error = null;
    try {
      await service.saveValidationResult(result);
      validationResults = [result, ...validationResults];
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to save validation result';
      throw e;
    } finally {
      loading = false;
    }
  }

  // Correction History Operations

  async function loadCorrectionHistory() {
    loading = true;
    error = null;
    try {
      correctionHistory = await service.getAllCorrectionHistory();
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to load correction history';
    } finally {
      loading = false;
    }
  }

  async function recordCorrection(
    eventId: string,
    aiPrediction: MacroData,
    userCorrection: MacroData,
    metadata: {
      imageUrl?: string;
      aiProvider: string;
      aiConfidence: number;
      category?: FoodCategory;
    }
  ) {
    loading = true;
    error = null;
    try {
      await service.recordCorrection(eventId, aiPrediction, userCorrection, metadata);
      // Reload correction history to get the new entry
      correctionHistory = await service.getAllCorrectionHistory();
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to record correction';
      throw e;
    } finally {
      loading = false;
    }
  }

  // Accuracy Metrics

  async function loadAccuracyMetrics(provider?: string, category?: FoodCategory) {
    loading = true;
    error = null;
    try {
      accuracyMetrics = await service.calculateAccuracyMetrics(provider, category);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to calculate accuracy metrics';
    } finally {
      loading = false;
    }
  }

  async function loadCorrectionPatterns() {
    loading = true;
    error = null;
    try {
      correctionPatterns = await service.analyzeCorrectionPatterns();
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to analyse correction patterns';
    } finally {
      loading = false;
    }
  }

  async function loadPromptEnhancements() {
    loading = true;
    error = null;
    try {
      promptEnhancements = await service.generatePromptEnhancements();
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to generate prompt enhancements';
    } finally {
      loading = false;
    }
  }

  // Export/Import

  async function exportTestDataset(): Promise<TestDatasetExport> {
    loading = true;
    error = null;
    try {
      return await service.exportTestDataset();
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to export test dataset';
      throw e;
    } finally {
      loading = false;
    }
  }

  async function importTestDataset(data: TestDatasetExport): Promise<DatasetImportResult> {
    loading = true;
    error = null;
    try {
      const result = await service.importTestDataset(data);
      // Reload entries after import
      testEntries = await service.getAllTestEntries();
      return result;
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to import test dataset';
      throw e;
    } finally {
      loading = false;
    }
  }

  async function importUSDAData(entries: USDAFoodEntry[]): Promise<DatasetImportResult> {
    loading = true;
    error = null;
    try {
      const result = await service.importUSDAData(entries);
      // Reload entries after import
      testEntries = await service.getAllTestEntries();
      return result;
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to import USDA data';
      throw e;
    } finally {
      loading = false;
    }
  }

  // Clear Operations

  async function clearTestDataset() {
    loading = true;
    error = null;
    try {
      await service.clearTestDataset();
      testEntries = [];
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to clear test dataset';
      throw e;
    } finally {
      loading = false;
    }
  }

  async function clearValidationResults() {
    loading = true;
    error = null;
    try {
      await service.clearValidationResults();
      validationResults = [];
      accuracyMetrics = null;
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to clear validation results';
      throw e;
    } finally {
      loading = false;
    }
  }

  async function clearCorrectionHistory() {
    loading = true;
    error = null;
    try {
      await service.clearCorrectionHistory();
      correctionHistory = [];
      correctionPatterns = [];
      promptEnhancements = [];
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to clear correction history';
      throw e;
    } finally {
      loading = false;
    }
  }

  // Derived values
  const testEntryCount = $derived(testEntries.length);
  const validationResultCount = $derived(validationResults.length);
  const correctionCount = $derived(correctionHistory.length);

  return {
    // State getters
    get testEntries() {
      return testEntries;
    },
    get validationResults() {
      return validationResults;
    },
    get correctionHistory() {
      return correctionHistory;
    },
    get accuracyMetrics() {
      return accuracyMetrics;
    },
    get correctionPatterns() {
      return correctionPatterns;
    },
    get promptEnhancements() {
      return promptEnhancements;
    },
    get loading() {
      return loading;
    },
    get error() {
      return error;
    },

    // Derived values
    get testEntryCount() {
      return testEntryCount;
    },
    get validationResultCount() {
      return validationResultCount;
    },
    get correctionCount() {
      return correctionCount;
    },

    // Test Dataset operations
    loadTestEntries,
    loadTestEntriesByCategory,
    loadTestEntriesBySource,
    createTestEntry,
    updateTestEntry,
    deleteTestEntry,

    // Validation Results operations
    loadValidationResults,
    saveValidationResult,

    // Correction History operations
    loadCorrectionHistory,
    recordCorrection,

    // Metrics operations
    loadAccuracyMetrics,
    loadCorrectionPatterns,
    loadPromptEnhancements,

    // Export/Import operations
    exportTestDataset,
    importTestDataset,
    importUSDAData,

    // Clear operations
    clearTestDataset,
    clearValidationResults,
    clearCorrectionHistory
  };
}

export const validationStore = createValidationStore();
