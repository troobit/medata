/**
 * Synthetic Test Image Generator
 * Creates test images with reference objects for volume estimation validation
 *
 * Note: This generates simple SVG-based test patterns that can be used
 * to validate the reference detection and volume estimation algorithms.
 */

import type { MacroData, FoodCategory, CreateTestDataInput } from '$lib/types';

/**
 * Reference object types for synthetic images
 */
export type SyntheticReferenceType = 'credit-card' | 'coin-au-dollar' | 'coin-au-50c';

/**
 * Food shape types for synthetic representations
 */
export type FoodShapeType = 'circle' | 'rectangle' | 'oval' | 'irregular';

/**
 * Configuration for synthetic food item
 */
export interface SyntheticFoodConfig {
  name: string;
  category: FoodCategory;
  shape: FoodShapeType;
  color: string;
  /** Width in mm */
  widthMm: number;
  /** Height in mm (for rectangle/oval) */
  heightMm?: number;
  /** Estimated depth/height in mm */
  depthMm: number;
  /** Known macros per serving */
  macros: MacroData;
}

/**
 * Configuration for generating a synthetic test image
 */
export interface SyntheticImageConfig {
  /** Image dimensions in pixels */
  widthPx: number;
  heightPx: number;
  /** Reference object */
  reference: SyntheticReferenceType;
  /** Position of reference (0-1 normalised) */
  referencePosition: { x: number; y: number };
  /** Food items to render */
  foods: SyntheticFoodConfig[];
  /** Background colour */
  backgroundColor: string;
}

/**
 * Reference object dimensions in mm
 */
const REFERENCE_DIMENSIONS: Record<SyntheticReferenceType, { width: number; height: number }> = {
  'credit-card': { width: 85.6, height: 53.98 },
  'coin-au-dollar': { width: 25, height: 25 },
  'coin-au-50c': { width: 31.51, height: 31.51 }
};

/**
 * Common food presets for synthetic generation
 */
export const SYNTHETIC_FOOD_PRESETS: SyntheticFoodConfig[] = [
  {
    name: 'Apple (medium)',
    category: 'fruit',
    shape: 'circle',
    color: '#dc2626',
    widthMm: 75,
    depthMm: 70,
    macros: { calories: 95, carbs: 25, protein: 0.5, fat: 0.3 }
  },
  {
    name: 'Banana',
    category: 'fruit',
    shape: 'oval',
    color: '#fbbf24',
    widthMm: 180,
    heightMm: 35,
    depthMm: 35,
    macros: { calories: 105, carbs: 27, protein: 1.3, fat: 0.4 }
  },
  {
    name: 'Slice of bread',
    category: 'grain',
    shape: 'rectangle',
    color: '#d97706',
    widthMm: 120,
    heightMm: 100,
    depthMm: 12,
    macros: { calories: 79, carbs: 15, protein: 2.7, fat: 1 }
  },
  {
    name: 'Chicken breast (150g)',
    category: 'protein',
    shape: 'oval',
    color: '#fef3c7',
    widthMm: 140,
    heightMm: 80,
    depthMm: 25,
    macros: { calories: 248, carbs: 0, protein: 46.5, fat: 5.4 }
  },
  {
    name: 'Broccoli floret',
    category: 'vegetable',
    shape: 'irregular',
    color: '#16a34a',
    widthMm: 50,
    depthMm: 60,
    macros: { calories: 15, carbs: 3, protein: 1.3, fat: 0.2 }
  },
  {
    name: 'Rice (1 cup cooked)',
    category: 'grain',
    shape: 'oval',
    color: '#fefce8',
    widthMm: 100,
    heightMm: 80,
    depthMm: 30,
    macros: { calories: 206, carbs: 45, protein: 4.3, fat: 0.4 }
  }
];

/**
 * Generate an SVG synthetic test image
 */
export function generateSyntheticSVG(config: SyntheticImageConfig): string {
  const { widthPx, heightPx, reference, referencePosition, foods, backgroundColor } = config;

  // Calculate scale (pixels per mm) based on reference object
  const refDims = REFERENCE_DIMENSIONS[reference];
  const refWidthPx = widthPx * 0.2; // Reference takes about 20% of image width
  const scale = refWidthPx / refDims.width;

  // Reference position in pixels
  const refX = referencePosition.x * widthPx;
  const refY = referencePosition.y * heightPx;
  const refHeightPx = refDims.height * scale;

  let svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${widthPx}" height="${heightPx}" viewBox="0 0 ${widthPx} ${heightPx}">`;

  // Background
  svg += `<rect width="100%" height="100%" fill="${backgroundColor}"/>`;

  // Reference object
  if (reference === 'credit-card') {
    // Card with rounded corners
    svg += `<rect x="${refX}" y="${refY}" width="${refWidthPx}" height="${refHeightPx}" rx="5" fill="#374151" stroke="#6b7280" stroke-width="2"/>`;
    svg += `<text x="${refX + refWidthPx / 2}" y="${refY + refHeightPx / 2}" fill="#9ca3af" font-size="12" text-anchor="middle" dominant-baseline="middle">CARD</text>`;
  } else {
    // Coin (circle)
    const coinRadius = refWidthPx / 2;
    svg += `<circle cx="${refX + coinRadius}" cy="${refY + coinRadius}" r="${coinRadius}" fill="#fbbf24" stroke="#d97706" stroke-width="2"/>`;
    svg += `<text x="${refX + coinRadius}" y="${refY + coinRadius}" fill="#78350f" font-size="10" text-anchor="middle" dominant-baseline="middle">$${reference === 'coin-au-dollar' ? '1' : '.50'}</text>`;
  }

  // Food items
  let foodX = widthPx * 0.4;
  let foodY = heightPx * 0.3;

  for (const food of foods) {
    const foodWidthPx = food.widthMm * scale;
    const foodHeightPx = (food.heightMm ?? food.widthMm) * scale;

    switch (food.shape) {
      case 'circle':
        svg += `<circle cx="${foodX + foodWidthPx / 2}" cy="${foodY + foodWidthPx / 2}" r="${foodWidthPx / 2}" fill="${food.color}" stroke="#00000033" stroke-width="2"/>`;
        break;
      case 'oval':
        svg += `<ellipse cx="${foodX + foodWidthPx / 2}" cy="${foodY + foodHeightPx / 2}" rx="${foodWidthPx / 2}" ry="${foodHeightPx / 2}" fill="${food.color}" stroke="#00000033" stroke-width="2"/>`;
        break;
      case 'rectangle':
        svg += `<rect x="${foodX}" y="${foodY}" width="${foodWidthPx}" height="${foodHeightPx}" rx="3" fill="${food.color}" stroke="#00000033" stroke-width="2"/>`;
        break;
      case 'irregular': {
        // Blob-like shape
        const points = generateIrregularPath(foodX, foodY, foodWidthPx, foodHeightPx);
        svg += `<path d="${points}" fill="${food.color}" stroke="#00000033" stroke-width="2"/>`;
        break;
      }
    }

    // Move to next position
    foodY += foodHeightPx + 20;
    if (foodY > heightPx * 0.7) {
      foodY = heightPx * 0.3;
      foodX += widthPx * 0.25;
    }
  }

  // Add scale indicator
  const scaleBarWidthMm = 50;
  const scaleBarWidthPx = scaleBarWidthMm * scale;
  svg += `<line x1="${widthPx - scaleBarWidthPx - 20}" y1="${heightPx - 30}" x2="${widthPx - 20}" y2="${heightPx - 30}" stroke="#fff" stroke-width="2"/>`;
  svg += `<text x="${widthPx - 20 - scaleBarWidthPx / 2}" y="${heightPx - 15}" fill="#fff" font-size="10" text-anchor="middle">${scaleBarWidthMm}mm</text>`;

  svg += '</svg>';
  return svg;
}

/**
 * Generate an irregular blob path
 */
function generateIrregularPath(x: number, y: number, width: number, height: number): string {
  const cx = x + width / 2;
  const cy = y + height / 2;
  const points: string[] = [];

  // Generate 8 points around the center with random variation
  for (let i = 0; i < 8; i++) {
    const angle = (i / 8) * Math.PI * 2;
    const r = (width / 2) * (0.7 + Math.sin(i * 1.5) * 0.3);
    const px = cx + Math.cos(angle) * r;
    const py = cy + Math.sin(angle) * r * (height / width);
    points.push(`${px},${py}`);
  }

  return `M ${points[0]} C ${points.slice(1).join(' ')} Z`;
}

/**
 * Convert SVG to data URL
 */
export function svgToDataUrl(svg: string): string {
  const encoded = encodeURIComponent(svg);
  return `data:image/svg+xml,${encoded}`;
}

/**
 * Generate a test dataset entry from synthetic config
 */
export function createSyntheticTestEntry(config: SyntheticImageConfig): CreateTestDataInput {
  const svg = generateSyntheticSVG(config);
  const imageUrl = svgToDataUrl(svg);

  // Aggregate macros from all foods
  const groundTruth: MacroData = {
    calories: 0,
    carbs: 0,
    protein: 0,
    fat: 0
  };

  for (const food of config.foods) {
    groundTruth.calories += food.macros.calories;
    groundTruth.carbs += food.macros.carbs;
    groundTruth.protein += food.macros.protein;
    groundTruth.fat += food.macros.fat;
  }

  return {
    imageUrl,
    groundTruth,
    source: 'manual-weighed',
    category: config.foods[0]?.category ?? 'mixed',
    description: `Synthetic: ${config.foods.map((f) => f.name).join(', ')}`,
    referenceObjects: [config.reference],
    items: config.foods.map((f) => ({
      name: f.name,
      quantity: 1,
      unit: 'serving',
      macros: f.macros
    }))
  };
}

/**
 * Generate a batch of synthetic test entries with common food combinations
 */
export function generateSyntheticTestBatch(): CreateTestDataInput[] {
  const entries: CreateTestDataInput[] = [];

  // Single items with credit card reference
  for (const food of SYNTHETIC_FOOD_PRESETS) {
    entries.push(
      createSyntheticTestEntry({
        widthPx: 800,
        heightPx: 600,
        reference: 'credit-card',
        referencePosition: { x: 0.05, y: 0.7 },
        foods: [food],
        backgroundColor: '#1f2937'
      })
    );
  }

  // Common meal combinations
  entries.push(
    createSyntheticTestEntry({
      widthPx: 800,
      heightPx: 600,
      reference: 'credit-card',
      referencePosition: { x: 0.05, y: 0.7 },
      foods: [SYNTHETIC_FOOD_PRESETS[2], SYNTHETIC_FOOD_PRESETS[3]], // Bread + chicken
      backgroundColor: '#1f2937'
    })
  );

  entries.push(
    createSyntheticTestEntry({
      widthPx: 800,
      heightPx: 600,
      reference: 'coin-au-dollar',
      referencePosition: { x: 0.1, y: 0.8 },
      foods: [SYNTHETIC_FOOD_PRESETS[5], SYNTHETIC_FOOD_PRESETS[4]], // Rice + broccoli
      backgroundColor: '#1f2937'
    })
  );

  return entries;
}
