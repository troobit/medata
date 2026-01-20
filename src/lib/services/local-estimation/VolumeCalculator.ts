/**
 * Workstream C: Volume Calculator
 * Estimates 3D volume from 2D regions using shape templates and heuristics.
 * Based on GoCARB research methodology.
 */

import type {
  FoodRegion,
  DetectedReference,
  VolumeEstimationResult
} from '$lib/types/local-estimation';

/**
 * Shape template for volume estimation
 */
export type ShapeTemplate = 'flat' | 'dome' | 'pile' | 'bowl' | 'cylinder' | 'irregular';

/**
 * Shape parameters for volume calculation
 */
interface ShapeParams {
  /** Height multiplier relative to equivalent radius */
  heightRatio: number;
  /** Volume correction factor */
  volumeMultiplier: number;
  /** Description for UI */
  description: string;
}

/**
 * Shape template definitions with height heuristics
 * Based on GoCARB research and empirical data
 */
const SHAPE_TEMPLATES: Record<ShapeTemplate, ShapeParams> = {
  flat: {
    heightRatio: 0.1,
    volumeMultiplier: 1.0,
    description: 'Flat food (sandwich, pizza slice)'
  },
  dome: {
    heightRatio: 0.4,
    volumeMultiplier: 0.67, // Hemisphere = 2/3 of cylinder
    description: 'Dome shape (rice, mashed potato)'
  },
  pile: {
    heightRatio: 0.6,
    volumeMultiplier: 0.5, // Cone-like = 1/3 of cylinder, but rounded
    description: 'Pile/mound (chips, salad)'
  },
  bowl: {
    heightRatio: 0.8,
    volumeMultiplier: 0.85,
    description: 'Bowl contents (soup, cereal)'
  },
  cylinder: {
    heightRatio: 1.0,
    volumeMultiplier: 1.0,
    description: 'Cylindrical (drink, container)'
  },
  irregular: {
    heightRatio: 0.35,
    volumeMultiplier: 0.6,
    description: 'Irregular shape (mixed plate)'
  }
};

/**
 * VolumeCalculator estimates 3D volume from 2D regions
 */
export class VolumeCalculator {
  /**
   * Estimate volume for a set of food regions
   */
  estimateVolume(
    regions: FoodRegion[],
    reference: DetectedReference | null,
    defaultShape: ShapeTemplate = 'dome'
  ): VolumeEstimationResult {
    const warnings: string[] = [];
    let totalVolumeMl = 0;
    let totalConfidence = 0;

    // Use reference scale, or estimate from image if not available
    const pixelsPerMm = reference?.pixelsPerMm ?? this.estimateDefaultScale();
    if (!reference) {
      warnings.push('No reference object detected. Using estimated scale.');
    }

    const processedRegions: FoodRegion[] = [];

    for (const region of regions) {
      // Calculate area in mm²
      const areaPx = this.calculatePolygonArea(region.boundary);
      const areaMm2 = areaPx / (pixelsPerMm * pixelsPerMm);

      // Estimate height using shape heuristics
      const equivalentRadius = Math.sqrt(areaMm2 / Math.PI);
      const shape = SHAPE_TEMPLATES[defaultShape];
      const heightMm = equivalentRadius * shape.heightRatio;

      // Calculate volume (cylinder approximation with shape multiplier)
      const cylinderVolume = areaMm2 * heightMm;
      const volumeMm3 = cylinderVolume * shape.volumeMultiplier;
      const volumeMl = volumeMm3 / 1000; // mm³ to mL

      totalVolumeMl += volumeMl;

      processedRegions.push({
        ...region,
        estimatedAreaMm2: Math.round(areaMm2),
        estimatedHeightMm: Math.round(heightMm),
        estimatedVolumeMl: Math.round(volumeMl)
      });
    }

    // Calculate confidence based on reference quality and region count
    const referenceConfidence = reference?.confidence ?? 0.5;
    const regionConfidence = regions.length > 0 ? Math.min(1, 0.7 + regions.length * 0.1) : 0;
    totalConfidence = referenceConfidence * 0.6 + regionConfidence * 0.4;

    // Add warnings for edge cases
    if (totalVolumeMl > 2000) {
      warnings.push('Large volume estimated. Please verify regions.');
    }
    if (totalVolumeMl < 10 && regions.length > 0) {
      warnings.push('Very small volume. Reference may be incorrect.');
    }

    return {
      regions: processedRegions,
      totalVolumeMl: Math.round(totalVolumeMl),
      confidence: Math.round(totalConfidence * 100) / 100,
      referenceUsed: reference ?? undefined,
      warnings: warnings.length > 0 ? warnings : undefined
    };
  }

  /**
   * Re-estimate volume with a different shape template
   */
  reestimateWithShape(
    previousResult: VolumeEstimationResult,
    shape: ShapeTemplate
  ): VolumeEstimationResult {
    const shapeParams = SHAPE_TEMPLATES[shape];
    const pixelsPerMm = previousResult.referenceUsed?.pixelsPerMm ?? this.estimateDefaultScale();

    let totalVolumeMl = 0;
    const updatedRegions: FoodRegion[] = [];

    for (const region of previousResult.regions) {
      if (!region.estimatedAreaMm2) continue;

      const areaMm2 = region.estimatedAreaMm2;
      const equivalentRadius = Math.sqrt(areaMm2 / Math.PI);
      const heightMm = equivalentRadius * shapeParams.heightRatio;
      const cylinderVolume = areaMm2 * heightMm;
      const volumeMm3 = cylinderVolume * shapeParams.volumeMultiplier;
      const volumeMl = volumeMm3 / 1000;

      totalVolumeMl += volumeMl;

      updatedRegions.push({
        ...region,
        estimatedHeightMm: Math.round(heightMm),
        estimatedVolumeMl: Math.round(volumeMl)
      });
    }

    return {
      ...previousResult,
      regions: updatedRegions,
      totalVolumeMl: Math.round(totalVolumeMl)
    };
  }

  /**
   * Calculate polygon area using Shoelace formula
   */
  calculatePolygonArea(points: Array<{ x: number; y: number }>): number {
    if (points.length < 3) return 0;

    let area = 0;
    const n = points.length;

    for (let i = 0; i < n; i++) {
      const j = (i + 1) % n;
      area += points[i].x * points[j].y;
      area -= points[j].x * points[i].y;
    }

    return Math.abs(area / 2);
  }

  /**
   * Calculate centroid of a polygon
   */
  calculateCentroid(points: Array<{ x: number; y: number }>): { x: number; y: number } {
    if (points.length === 0) return { x: 0, y: 0 };

    let sumX = 0;
    let sumY = 0;

    for (const point of points) {
      sumX += point.x;
      sumY += point.y;
    }

    return {
      x: sumX / points.length,
      y: sumY / points.length
    };
  }

  /**
   * Estimate default scale when no reference is available
   * Assumes a typical phone photo of a plate
   */
  private estimateDefaultScale(): number {
    // Typical assumption: image width ~= 20cm in real life
    // This is very rough and should trigger a warning
    return 3; // ~3 pixels per mm for a 1200px wide image of a 40cm scene
  }

  /**
   * Get available shape templates
   */
  getShapeTemplates(): Array<{ id: ShapeTemplate; params: ShapeParams }> {
    return Object.entries(SHAPE_TEMPLATES).map(([id, params]) => ({
      id: id as ShapeTemplate,
      params
    }));
  }

  /**
   * Suggest shape template based on food type
   */
  suggestShape(foodName: string): ShapeTemplate {
    const name = foodName.toLowerCase();

    // Flat foods
    if (
      name.includes('pizza') ||
      name.includes('sandwich') ||
      name.includes('toast') ||
      name.includes('bread') ||
      name.includes('pancake') ||
      name.includes('flatbread')
    ) {
      return 'flat';
    }

    // Dome/mound foods
    if (
      name.includes('rice') ||
      name.includes('mash') ||
      name.includes('potato') ||
      name.includes('pasta') ||
      name.includes('noodle') ||
      name.includes('oatmeal')
    ) {
      return 'dome';
    }

    // Pile foods
    if (
      name.includes('chip') ||
      name.includes('fries') ||
      name.includes('salad') ||
      name.includes('veg') ||
      name.includes('fruit') ||
      name.includes('berr')
    ) {
      return 'pile';
    }

    // Bowl/liquid foods
    if (
      name.includes('soup') ||
      name.includes('stew') ||
      name.includes('curry') ||
      name.includes('cereal') ||
      name.includes('yogurt')
    ) {
      return 'bowl';
    }

    // Default to irregular for mixed/unknown
    return 'irregular';
  }

  /**
   * Calculate uncertainty bounds (±%)
   */
  calculateUncertainty(result: VolumeEstimationResult): {
    low: number;
    high: number;
    percentage: number;
  } {
    // Base uncertainty of 30% (from GoCARB research)
    let baseUncertainty = 0.3;

    // Increase uncertainty if no reference
    if (!result.referenceUsed) {
      baseUncertainty = 0.5;
    } else if (result.referenceUsed.confidence < 0.7) {
      baseUncertainty = 0.4;
    }

    // Decrease uncertainty slightly for high confidence
    if (result.confidence > 0.8) {
      baseUncertainty *= 0.9;
    }

    const percentage = Math.round(baseUncertainty * 100);
    const low = Math.round(result.totalVolumeMl * (1 - baseUncertainty));
    const high = Math.round(result.totalVolumeMl * (1 + baseUncertainty));

    return { low, high, percentage };
  }
}

export const volumeCalculator = new VolumeCalculator();
export { SHAPE_TEMPLATES };
