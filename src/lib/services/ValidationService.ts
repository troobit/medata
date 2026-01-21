import { v4 as uuidv4 } from 'uuid';
import type {
  TestDatasetEntry,
  CreateTestDataInput,
  UpdateTestDataInput,
  ValidationResult,
  CorrectionHistoryEntry,
  MacroData,
  MacroErrorMetrics,
  AccuracyMetrics,
  FoodCategory,
  GroundTruthSource,
  TestDatasetExport,
  USDAFoodEntry,
  DatasetImportResult,
  CorrectionPatternStats,
  PromptEnhancement
} from '$lib/types';
import type { IValidationRepository } from '$lib/repositories';

/**
 * Business logic layer for AI model validation
 * Handles test datasets, validation results, and correction analysis
 */
export class ValidationService {
  constructor(private repository: IValidationRepository) {}

  // Test Dataset Operations

  async createTestEntry(input: CreateTestDataInput): Promise<TestDatasetEntry> {
    return this.repository.createTestEntry(input);
  }

  async getTestEntry(id: string): Promise<TestDatasetEntry | null> {
    return this.repository.getTestEntryById(id);
  }

  async updateTestEntry(id: string, updates: UpdateTestDataInput): Promise<TestDatasetEntry> {
    return this.repository.updateTestEntry(id, updates);
  }

  async deleteTestEntry(id: string): Promise<void> {
    return this.repository.deleteTestEntry(id);
  }

  async getAllTestEntries(): Promise<TestDatasetEntry[]> {
    return this.repository.getAllTestEntries();
  }

  async getTestEntriesByCategory(category: FoodCategory): Promise<TestDatasetEntry[]> {
    return this.repository.getTestEntriesByCategory(category);
  }

  async getTestEntriesBySource(source: GroundTruthSource): Promise<TestDatasetEntry[]> {
    return this.repository.getTestEntriesBySource(source);
  }

  // Validation Result Operations

  async saveValidationResult(result: ValidationResult): Promise<void> {
    return this.repository.saveValidationResult(result);
  }

  async getValidationResults(testEntryId: string): Promise<ValidationResult[]> {
    return this.repository.getValidationResults(testEntryId);
  }

  async getAllValidationResults(): Promise<ValidationResult[]> {
    return this.repository.getAllValidationResults();
  }

  // Correction History Operations

  async saveCorrectionHistory(entry: CorrectionHistoryEntry): Promise<void> {
    return this.repository.saveCorrectionHistory(entry);
  }

  async getAllCorrectionHistory(): Promise<CorrectionHistoryEntry[]> {
    return this.repository.getAllCorrectionHistory();
  }

  async getCorrectionHistoryByCategory(category: FoodCategory): Promise<CorrectionHistoryEntry[]> {
    return this.repository.getCorrectionHistoryByCategory(category);
  }

  /**
   * Record a user correction for learning
   */
  async recordCorrection(
    eventId: string,
    aiPrediction: MacroData,
    userCorrection: MacroData,
    metadata: {
      imageUrl?: string;
      aiProvider: string;
      aiConfidence: number;
      category?: FoodCategory;
      aiItems?: CorrectionHistoryEntry['aiItems'];
      correctedItems?: CorrectionHistoryEntry['correctedItems'];
    }
  ): Promise<void> {
    const entry: CorrectionHistoryEntry = {
      id: uuidv4(),
      eventId,
      imageUrl: metadata.imageUrl,
      aiPrediction,
      userCorrection,
      aiProvider: metadata.aiProvider,
      aiConfidence: metadata.aiConfidence,
      category: metadata.category,
      aiItems: metadata.aiItems,
      correctedItems: metadata.correctedItems,
      source: 'ai',
      timestamp: new Date()
    };

    await this.repository.saveCorrectionHistory(entry);
  }

  // Error Metrics Calculation

  /**
   * Calculate Mean Absolute Error for macro predictions
   */
  calculateMAE(predicted: MacroData, actual: MacroData): MacroErrorMetrics {
    const caloriesError = Math.abs(predicted.calories - actual.calories);
    const carbsError = Math.abs(predicted.carbs - actual.carbs);
    const proteinError = Math.abs(predicted.protein - actual.protein);
    const fatError = Math.abs(predicted.fat - actual.fat);

    // Weighted average (carbs weighted higher for diabetes management)
    const overall = caloriesError * 0.1 + carbsError * 0.5 + proteinError * 0.2 + fatError * 0.2;

    return {
      calories: caloriesError,
      carbs: carbsError,
      protein: proteinError,
      fat: fatError,
      overall
    };
  }

  /**
   * Calculate Mean Absolute Percentage Error for macro predictions
   */
  calculateMAPE(predicted: MacroData, actual: MacroData): MacroErrorMetrics {
    const safePercentage = (pred: number, act: number): number => {
      if (act === 0) return pred === 0 ? 0 : 100; // If actual is 0, any prediction is 100% error
      return Math.abs((pred - act) / act) * 100;
    };

    const caloriesError = safePercentage(predicted.calories, actual.calories);
    const carbsError = safePercentage(predicted.carbs, actual.carbs);
    const proteinError = safePercentage(predicted.protein, actual.protein);
    const fatError = safePercentage(predicted.fat, actual.fat);

    // Weighted average
    const overall = caloriesError * 0.1 + carbsError * 0.5 + proteinError * 0.2 + fatError * 0.2;

    return {
      calories: caloriesError,
      carbs: carbsError,
      protein: proteinError,
      fat: fatError,
      overall
    };
  }

  /**
   * Calculate aggregated accuracy metrics
   */
  async calculateAccuracyMetrics(
    provider?: string,
    category?: FoodCategory
  ): Promise<AccuracyMetrics> {
    let results = await this.repository.getAllValidationResults();

    // Filter by provider if specified
    if (provider) {
      results = results.filter((r) => r.aiProvider === provider);
    }

    // Filter by category - need to cross-reference with test entries
    if (category) {
      const testEntries = await this.repository.getAllTestEntries();
      const categoryEntryIds = new Set(
        testEntries.filter((e) => e.category === category).map((e) => e.id)
      );
      results = results.filter((r) => categoryEntryIds.has(r.testEntryId));
    }

    if (results.length === 0) {
      return {
        provider: provider || 'all',
        category,
        sampleCount: 0,
        mae: { calories: 0, carbs: 0, protein: 0, fat: 0, overall: 0 },
        mape: { calories: 0, carbs: 0, protein: 0, fat: 0, overall: 0 },
        avgConfidence: 0,
        avgProcessingTimeMs: 0
      };
    }

    // Calculate averages
    const avgMAE: MacroErrorMetrics = {
      calories: results.reduce((sum, r) => sum + r.mae.calories, 0) / results.length,
      carbs: results.reduce((sum, r) => sum + r.mae.carbs, 0) / results.length,
      protein: results.reduce((sum, r) => sum + r.mae.protein, 0) / results.length,
      fat: results.reduce((sum, r) => sum + r.mae.fat, 0) / results.length,
      overall: results.reduce((sum, r) => sum + r.mae.overall, 0) / results.length
    };

    const avgMAPE: MacroErrorMetrics = {
      calories: results.reduce((sum, r) => sum + r.mape.calories, 0) / results.length,
      carbs: results.reduce((sum, r) => sum + r.mape.carbs, 0) / results.length,
      protein: results.reduce((sum, r) => sum + r.mape.protein, 0) / results.length,
      fat: results.reduce((sum, r) => sum + r.mape.fat, 0) / results.length,
      overall: results.reduce((sum, r) => sum + r.mape.overall, 0) / results.length
    };

    return {
      provider: provider || 'all',
      category,
      sampleCount: results.length,
      mae: avgMAE,
      mape: avgMAPE,
      avgConfidence: results.reduce((sum, r) => sum + r.confidence, 0) / results.length,
      avgProcessingTimeMs: results.reduce((sum, r) => sum + r.processingTimeMs, 0) / results.length
    };
  }

  /**
   * Analyze correction patterns by category
   */
  async analyzeCorrectionPatterns(): Promise<CorrectionPatternStats[]> {
    const corrections = await this.repository.getAllCorrectionHistory();

    // Group by category
    const byCategory = new Map<FoodCategory, CorrectionHistoryEntry[]>();
    for (const correction of corrections) {
      if (correction.category) {
        const existing = byCategory.get(correction.category) || [];
        existing.push(correction);
        byCategory.set(correction.category, existing);
      }
    }

    const stats: CorrectionPatternStats[] = [];

    for (const [category, entries] of byCategory) {
      const overestimation: MacroErrorMetrics = {
        calories: 0,
        carbs: 0,
        protein: 0,
        fat: 0,
        overall: 0
      };
      const underestimation: MacroErrorMetrics = {
        calories: 0,
        carbs: 0,
        protein: 0,
        fat: 0,
        overall: 0
      };
      let overCount = 0;
      let underCount = 0;
      let totalConfidence = 0;

      for (const entry of entries) {
        const diff = {
          calories: entry.aiPrediction.calories - entry.userCorrection.calories,
          carbs: entry.aiPrediction.carbs - entry.userCorrection.carbs,
          protein: entry.aiPrediction.protein - entry.userCorrection.protein,
          fat: entry.aiPrediction.fat - entry.userCorrection.fat
        };

        // Track overestimation (positive diff) and underestimation (negative diff)
        for (const [key, value] of Object.entries(diff) as [keyof MacroData, number][]) {
          if (key === 'alcohol') continue;
          if (value > 0) {
            overestimation[key] += value;
            overCount++;
          } else if (value < 0) {
            underestimation[key] += Math.abs(value);
            underCount++;
          }
        }

        totalConfidence += entry.aiConfidence;
      }

      // Average the values
      const fields: (keyof MacroErrorMetrics)[] = ['calories', 'carbs', 'protein', 'fat'];
      for (const field of fields) {
        if (overCount > 0) overestimation[field] /= entries.length;
        if (underCount > 0) underestimation[field] /= entries.length;
      }

      stats.push({
        category,
        avgOverestimation: overestimation,
        avgUnderestimation: underestimation,
        correctionCount: entries.length,
        avgConfidenceWhenWrong: totalConfidence / entries.length
      });
    }

    return stats;
  }

  /**
   * Generate prompt enhancement suggestions from correction patterns
   */
  async generatePromptEnhancements(): Promise<PromptEnhancement[]> {
    const patterns = await this.analyzeCorrectionPatterns();
    const enhancements: PromptEnhancement[] = [];

    const MIN_SAMPLE_SIZE = 5;
    const SIGNIFICANT_ERROR_PERCENT = 10;

    for (const pattern of patterns) {
      if (pattern.correctionCount < MIN_SAMPLE_SIZE) continue;

      const fields: (keyof MacroData)[] = ['calories', 'carbs', 'protein', 'fat'];

      for (const field of fields) {
        const over = pattern.avgOverestimation[field as keyof MacroErrorMetrics];
        const under = pattern.avgUnderestimation[field as keyof MacroErrorMetrics];

        // Check if there's a consistent bias
        if (over > under && over > SIGNIFICANT_ERROR_PERCENT) {
          enhancements.push({
            category: pattern.category,
            adjustment: 'decrease',
            field,
            percentageAdjustment: Math.min(over, 30), // Cap at 30%
            confidence: Math.min(pattern.correctionCount / 20, 1), // More samples = more confident
            sampleSize: pattern.correctionCount
          });
        } else if (under > over && under > SIGNIFICANT_ERROR_PERCENT) {
          enhancements.push({
            category: pattern.category,
            adjustment: 'increase',
            field,
            percentageAdjustment: Math.min(under, 30),
            confidence: Math.min(pattern.correctionCount / 20, 1),
            sampleSize: pattern.correctionCount
          });
        }
      }
    }

    return enhancements;
  }

  // Export/Import Operations

  /**
   * Export test dataset to JSON
   */
  async exportTestDataset(): Promise<TestDatasetExport> {
    const entries = await this.repository.getAllTestEntries();

    // Collect unique sources and categories
    const sources = new Set<GroundTruthSource>();
    const categories = new Set<FoodCategory>();
    for (const entry of entries) {
      sources.add(entry.source);
      if (entry.category) categories.add(entry.category);
    }

    return {
      version: '1.0',
      exportedAt: new Date().toISOString(),
      count: entries.length,
      entries,
      metadata: {
        sources: Array.from(sources),
        categories: Array.from(categories)
      }
    };
  }

  /**
   * Import test dataset from JSON
   */
  async importTestDataset(data: TestDatasetExport): Promise<DatasetImportResult> {
    const errors: Array<{ line: number; message: string }> = [];
    let imported = 0;
    let skipped = 0;

    for (let i = 0; i < data.entries.length; i++) {
      const entry = data.entries[i];
      try {
        // Validate required fields
        if (!entry.imageUrl || !entry.groundTruth || !entry.source) {
          errors.push({ line: i + 1, message: 'Missing required fields' });
          skipped++;
          continue;
        }

        await this.repository.createTestEntry({
          imageUrl: entry.imageUrl,
          groundTruth: entry.groundTruth,
          source: entry.source,
          category: entry.category,
          description: entry.description,
          sourceReference: entry.sourceReference,
          items: entry.items,
          referenceObjects: entry.referenceObjects
        });
        imported++;
      } catch (e) {
        errors.push({ line: i + 1, message: e instanceof Error ? e.message : 'Unknown error' });
        skipped++;
      }
    }

    return { success: errors.length === 0, imported, skipped, errors };
  }

  /**
   * Import USDA FNDDS data (simplified - requires images to be added separately)
   */
  async importUSDAData(entries: USDAFoodEntry[]): Promise<DatasetImportResult> {
    const errors: Array<{ line: number; message: string }> = [];
    let imported = 0;
    let skipped = 0;

    for (let i = 0; i < entries.length; i++) {
      const usda = entries[i];
      try {
        // Extract macros from USDA nutrients
        const getNutrient = (name: string): number => {
          const nutrient = usda.nutrients.find((n) =>
            n.nutrientName.toLowerCase().includes(name.toLowerCase())
          );
          return nutrient?.amount || 0;
        };

        const groundTruth: MacroData = {
          calories: getNutrient('energy'),
          carbs: getNutrient('carbohydrate'),
          protein: getNutrient('protein'),
          fat: getNutrient('total lipid')
        };

        // USDA entries don't have images - they need to be matched later
        // Create a placeholder entry that can be updated with images
        await this.repository.createTestEntry({
          imageUrl: '', // Placeholder - needs to be updated
          groundTruth,
          source: 'usda',
          sourceReference: usda.fdcId.toString(),
          description: usda.description,
          category: this.inferCategory(usda.description)
        });
        imported++;
      } catch (e) {
        errors.push({ line: i + 1, message: e instanceof Error ? e.message : 'Unknown error' });
        skipped++;
      }
    }

    return { success: errors.length === 0, imported, skipped, errors };
  }

  /**
   * Infer food category from description
   */
  private inferCategory(description: string): FoodCategory {
    const lower = description.toLowerCase();

    if (
      lower.includes('bread') ||
      lower.includes('rice') ||
      lower.includes('pasta') ||
      lower.includes('cereal')
    ) {
      return 'grain';
    }
    if (
      lower.includes('chicken') ||
      lower.includes('beef') ||
      lower.includes('fish') ||
      lower.includes('egg')
    ) {
      return 'protein';
    }
    if (lower.includes('milk') || lower.includes('cheese') || lower.includes('yogurt')) {
      return 'dairy';
    }
    if (
      lower.includes('apple') ||
      lower.includes('banana') ||
      lower.includes('orange') ||
      lower.includes('fruit')
    ) {
      return 'fruit';
    }
    if (
      lower.includes('carrot') ||
      lower.includes('broccoli') ||
      lower.includes('salad') ||
      lower.includes('vegetable')
    ) {
      return 'vegetable';
    }
    if (lower.includes('oil') || lower.includes('butter') || lower.includes('cream')) {
      return 'fat';
    }
    if (
      lower.includes('soda') ||
      lower.includes('juice') ||
      lower.includes('coffee') ||
      lower.includes('tea')
    ) {
      return 'beverage';
    }
    if (
      lower.includes('cookie') ||
      lower.includes('chip') ||
      lower.includes('candy') ||
      lower.includes('snack')
    ) {
      return 'snack';
    }

    return 'other';
  }

  // Clear Operations

  async clearTestDataset(): Promise<void> {
    return this.repository.clearTestDataset();
  }

  async clearValidationResults(): Promise<void> {
    return this.repository.clearValidationResults();
  }

  async clearCorrectionHistory(): Promise<void> {
    return this.repository.clearCorrectionHistory();
  }
}
