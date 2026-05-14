/**
 * Mock recognition service for development and testing.
 * Returns hardcoded food analysis data after a simulated delay.
 */
import type { IRecognitionService, FoodAnalysisResult } from "./recognition.js";

const MOCK_RESULT: FoodAnalysisResult = {
  items: [
    {
      name: "Grilled Chicken Breast",
      carbs: 0,
      protein: 31,
      fat: 3.6,
      confidence: 0.92,
    },
    {
      name: "Steamed Broccoli",
      carbs: 7,
      protein: 3,
      fat: 0.4,
      confidence: 0.88,
    },
    {
      name: "Brown Rice (1 cup)",
      carbs: 45,
      protein: 5,
      fat: 1.6,
      confidence: 0.85,
    },
  ],
  overallConfidence: 0.88,
  notes: "[MOCK] Simulated response — no backend call was made.",
};

export class MockRecognitionService implements IRecognitionService {
  isReady(): boolean {
    return true;
  }

  getBackendType(): string {
    return "mock";
  }

  async analyse(_image: Blob): Promise<FoodAnalysisResult> {
    const delay = 500 + Math.random() * 1000;
    await new Promise((resolve) => setTimeout(resolve, delay));
    return MOCK_RESULT;
  }
}
