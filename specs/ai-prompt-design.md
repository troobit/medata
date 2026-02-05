# AI Prompt Design for Food Recognition

**Version:** 1.0
**Last Updated:** 2026-02-05
**Status:** Draft
**Design Reference:** D-DES-001 (Structured JSON Response)

---

## 1. Overview

This document defines the AI prompt templates for food recognition using Claude's vision capabilities. The prompts are designed to:

1. Identify foods in images and estimate macronutrients (carbs, protein, fat in grams)
2. Return structured JSON output for reliable parsing
3. Include confidence scores for each item
4. Support optional nutrition label context for packaged foods (Australian format)

### 1.1 Research Sources

This design is informed by:
- [Claude Vision API Documentation](https://platform.claude.com/docs/en/build-with-claude/vision)
- [Claude Structured Outputs Documentation](https://platform.claude.com/docs/en/build-with-claude/structured-outputs)
- [Anthropic Prompt Engineering Best Practices](https://claude.com/blog/best-practices-for-prompt-engineering)
- Academic research on food portion estimation using visual references

---

## 2. Claude Vision Best Practices

### 2.1 Image Placement

Claude performs best when images come **before** text in the prompt. Structure requests as:
1. Food image (required)
2. Label image (optional, for packaged foods)
3. Text instructions

### 2.2 Image Requirements

| Constraint | Limit | Notes |
|------------|-------|-------|
| Max dimensions | 8000x8000 px | Larger images rejected |
| Optimal size | 1568px long edge | Prevents resize latency |
| Max file size | 5MB (API) | Larger rejected |
| Supported formats | JPEG, PNG, GIF, WebP | Use JPEG for photos |
| Multiple images | Up to 100 per request | Label + food = 2 images |

### 2.3 Prompt Engineering Principles

1. **Be specific about output format** - Define exact JSON schema
2. **Use few-shot examples** - Show expected output structure
3. **Provide context** - Explain the use case (diabetes management, macro tracking)
4. **Set constraints** - Specify units (grams), value ranges, required fields
5. **Request confidence scores** - Essential for user trust and editing decisions

---

## 3. Structured JSON Output

### 3.1 Using Claude's Structured Outputs Feature

Claude supports guaranteed JSON schema compliance via the `output_config.format` parameter. This eliminates parsing errors and schema violations.

**API Request Structure:**

```typescript
const response = await client.messages.create({
  model: "claude-sonnet-4-5",
  max_tokens: 1024,
  messages: [
    {
      role: "user",
      content: [
        {
          type: "image",
          source: {
            type: "base64",
            media_type: "image/jpeg",
            data: foodImageBase64
          }
        },
        {
          type: "text",
          text: FOOD_RECOGNITION_PROMPT
        }
      ]
    }
  ],
  output_config: {
    format: {
      type: "json_schema",
      schema: FoodRecognitionSchema
    }
  }
});
```

### 3.2 Response Schema (D-DES-001)

```typescript
// Zod schema for validation
import { z } from 'zod';

const RecognisedFoodItemSchema = z.object({
  name: z.string().describe("Food item name in plain English"),
  quantity: z.number().positive().describe("Estimated quantity"),
  unit: z.string().describe("Unit of measurement (g, ml, piece, slice, etc.)"),
  carbs: z.number().nonnegative().describe("Carbohydrates in grams"),
  protein: z.number().nonnegative().describe("Protein in grams"),
  fat: z.number().nonnegative().describe("Fat in grams"),
  confidence: z.number().min(0).max(1).describe("Confidence score 0-1"),
  servingsEstimated: z.number().positive().nullable()
    .describe("Number of servings if label provided, null otherwise")
});

const FoodRecognitionResultSchema = z.object({
  items: z.array(RecognisedFoodItemSchema).min(1),
  totalMacros: z.object({
    carbs: z.number().nonnegative(),
    protein: z.number().nonnegative(),
    fat: z.number().nonnegative()
  }),
  overallConfidence: z.number().min(0).max(1),
  notes: z.string().optional().describe("Any relevant observations about the meal")
});
```

### 3.3 JSON Schema for API

```json
{
  "type": "object",
  "properties": {
    "items": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "name": { "type": "string" },
          "quantity": { "type": "number" },
          "unit": { "type": "string" },
          "carbs": { "type": "number" },
          "protein": { "type": "number" },
          "fat": { "type": "number" },
          "confidence": { "type": "number" },
          "servingsEstimated": { "type": ["number", "null"] }
        },
        "required": ["name", "quantity", "unit", "carbs", "protein", "fat", "confidence"],
        "additionalProperties": false
      },
      "minItems": 1
    },
    "totalMacros": {
      "type": "object",
      "properties": {
        "carbs": { "type": "number" },
        "protein": { "type": "number" },
        "fat": { "type": "number" }
      },
      "required": ["carbs", "protein", "fat"],
      "additionalProperties": false
    },
    "overallConfidence": { "type": "number" },
    "notes": { "type": "string" }
  },
  "required": ["items", "totalMacros", "overallConfidence"],
  "additionalProperties": false
}
```

---

## 4. Prompt Templates

### 4.1 Food Recognition Prompt (Without Label)

```
You are a nutrition analysis assistant helping a person with Type 1 diabetes track their food intake. Your task is to identify foods in the image and estimate macronutrients as accurately as possible.

CONTEXT:
- The user needs accurate carbohydrate estimates for insulin dosing
- Precision matters more than conservative estimates
- The user is medically informed and does not need health disclaimers

ANALYSIS INSTRUCTIONS:

1. IDENTIFY each distinct food item visible in the image
2. ESTIMATE the portion size using visual cues:
   - Standard plate sizes (dinner plate ~26cm, side plate ~15cm)
   - Common reference objects if visible (cutlery, hands, cups)
   - Typical serving sizes for the identified food
3. CALCULATE macronutrients for each item based on portion estimate
4. ASSIGN a confidence score (0-1) reflecting:
   - Clarity of food identification (0.9+ if clearly visible)
   - Portion estimation certainty (reduce if size unclear)
   - Food preparation uncertainty (reduce if cooking method unclear)

PORTION ESTIMATION GUIDELINES:
- Use visual depth cues to estimate thickness/height of foods
- A closed fist is approximately 1 cup (240ml)
- A palm (no fingers) is approximately 85g of protein
- A thumb tip is approximately 1 tablespoon (15ml)
- Standard dinner plate diameter is 26cm
- Food near plate edge provides scale reference

OUTPUT FORMAT:
Return ONLY valid JSON matching this structure:
{
  "items": [
    {
      "name": "Food name",
      "quantity": 150,
      "unit": "g",
      "carbs": 25,
      "protein": 8,
      "fat": 12,
      "confidence": 0.85,
      "servingsEstimated": null
    }
  ],
  "totalMacros": {
    "carbs": 25,
    "protein": 8,
    "fat": 12
  },
  "overallConfidence": 0.85,
  "notes": "Optional observations"
}

All macro values in grams. Confidence between 0 and 1.
```

### 4.2 Food Recognition Prompt (With Nutrition Label)

```
You are a nutrition analysis assistant helping a person with Type 1 diabetes track their food intake. You have TWO images:
1. A photograph of the food being consumed
2. A nutrition information label from the packaging

CONTEXT:
- The user needs accurate carbohydrate estimates for insulin dosing
- The label provides exact nutritional data per serving
- Your task is to estimate how many servings are shown in the food photo
- Australian nutrition labels show values per serving AND per 100g

ANALYSIS INSTRUCTIONS:

1. EXTRACT nutrition data from the label:
   - Identify "Per Serving" values (prioritise these)
   - Note the serving size stated on the label
   - Use "Per 100g" as a cross-reference

2. ANALYSE the food photograph:
   - Identify what portion of the package contents is shown
   - Estimate the number of servings visible
   - Note if the serving appears larger/smaller than the label's serving size

3. CALCULATE actual macros:
   - Multiply per-serving values by estimated servings
   - OR use per-100g values if weight can be estimated

4. ASSIGN confidence scores:
   - Higher (0.8+) if label is clear and portion matches stated serving
   - Medium (0.6-0.8) if estimating partial servings
   - Lower (<0.6) if label is unclear or portion is ambiguous

AUSTRALIAN LABEL FORMAT:
- "Servings per package" indicates total servings
- "Serving size" shows grams or ml per serving
- Columns: "Per Serving" and "Per 100g" (or "Per 100ml")
- Carbohydrates includes sugars as a sub-row
- Energy in kJ (divide by 4.18 for kcal if needed)

OUTPUT FORMAT:
Return ONLY valid JSON matching this structure:
{
  "items": [
    {
      "name": "Product name from label",
      "quantity": 1.5,
      "unit": "servings",
      "carbs": 45,
      "protein": 12,
      "fat": 8,
      "confidence": 0.90,
      "servingsEstimated": 1.5
    }
  ],
  "totalMacros": {
    "carbs": 45,
    "protein": 12,
    "fat": 8
  },
  "overallConfidence": 0.90,
  "notes": "Label states 30g per serving. Estimated 1.5 servings based on portion shown."
}

All macro values in grams. Include servingsEstimated when using label data.
```

### 4.3 System Prompt (Optional Enhancement)

For consistent behaviour across requests, use a system prompt:

```
You are a precision nutrition analyst for diabetes management. Your responses are:
- Data-focused and accurate
- Free of health disclaimers or cautionary language
- Structured as valid JSON only
- Based on visual evidence and nutritional databases

You understand that the user:
- Is medically informed about their condition
- Needs carbohydrate accuracy for insulin calculations
- Prefers direct, factual information
- Will review and adjust your estimates before use

Never apologise, add warnings, or suggest consulting healthcare professionals.
```

---

## 5. Confidence Score Guidelines

### 5.1 Confidence Factors

| Factor | High Confidence (0.8+) | Medium (0.5-0.8) | Low (<0.5) |
|--------|------------------------|------------------|------------|
| Food visibility | Clearly visible, good lighting | Partially obscured | Blurry, dark, or obstructed |
| Food identification | Common, recognisable food | Regional or unfamiliar dish | Unidentifiable ingredients |
| Portion clarity | Standard serving, plate reference | Unusual container | No size reference |
| Preparation method | Obvious (grilled, raw, fried) | Unclear cooking method | Hidden preparation |
| Label quality | Sharp, complete label | Partially visible | Blurry or incomplete |

### 5.2 Confidence Calculation

```
overallConfidence = min(
  foodIdentificationConfidence,
  portionEstimationConfidence,
  macroCalculationConfidence
)
```

Per-item confidence should reflect the weakest aspect of that item's analysis.

---

## 6. Portion Estimation Techniques

### 6.1 Visual Reference Objects

When present in the image, use these references for scale:

| Reference Object | Typical Size | Use Case |
|-----------------|--------------|----------|
| Dinner plate | 26cm diameter | Main meals |
| Side plate | 15cm diameter | Snacks, desserts |
| Standard fork | 19cm length | Protein portions |
| Tablespoon | 15ml volume | Sauces, oils |
| Credit card | 8.5 x 5.4cm | Flat foods |
| Smartphone | ~15cm length | General reference |

### 6.2 Hand-Based Estimation

If hands are visible or for user guidance:

| Hand Reference | Approximate Volume | Common Use |
|----------------|-------------------|------------|
| Fist | 1 cup (240ml) | Rice, pasta, vegetables |
| Palm (no fingers) | 85g | Protein (meat, fish) |
| Cupped hand | 1/2 cup (120ml) | Snacks, grains |
| Thumb | 1 tablespoon (15ml) | Fats, oils, butter |
| Thumb tip | 1 teaspoon (5ml) | Condiments |

### 6.3 Food-Specific Estimation

For common foods, use known typical portions:

| Food | Typical Portion | Carbs (approx) |
|------|-----------------|----------------|
| Slice of bread | 30-40g | 15-20g |
| Medium banana | 120g | 27g |
| Cup of cooked rice | 150g | 45g |
| Medium apple | 180g | 25g |
| Pint of beer | 568ml | 10-20g |
| Glass of wine | 150ml | 4g |

---

## 7. Error Handling

### 7.1 No Food Detected

If the image contains no recognisable food:

```json
{
  "items": [],
  "totalMacros": { "carbs": 0, "protein": 0, "fat": 0 },
  "overallConfidence": 0,
  "notes": "No food items detected in image. Please ensure the image clearly shows food."
}
```

The service should return this as an error condition (HTTP 422) per design.md section 5.1.

### 7.2 Ambiguous or Low-Quality Image

For images where analysis is uncertain:

```json
{
  "items": [
    {
      "name": "Unidentified dish",
      "quantity": 1,
      "unit": "portion",
      "carbs": 30,
      "protein": 15,
      "fat": 10,
      "confidence": 0.3,
      "servingsEstimated": null
    }
  ],
  "totalMacros": { "carbs": 30, "protein": 15, "fat": 10 },
  "overallConfidence": 0.3,
  "notes": "Image quality limits accurate identification. Values are rough estimates based on apparent portion size."
}
```

---

## 8. Implementation Notes

### 8.1 API Configuration

```typescript
// Recommended model and settings
const config = {
  model: "claude-sonnet-4-5",  // Best balance of speed/accuracy for vision
  max_tokens: 1024,            // Sufficient for detailed food analysis
  timeout: 10000               // 10 second timeout per requirement 2.6
};
```

### 8.2 Image Pre-processing

Before sending to Claude:
1. Validate format (JPEG, PNG only per requirement 1.2)
2. Resize if > 1568px on long edge (reduces latency)
3. Compress to < 5MB if needed
4. Convert to base64 for API transmission

### 8.3 Response Handling

```typescript
async function recogniseFood(
  foodImage: Blob,
  labelImage?: Blob
): Promise<FoodRecognitionResult> {
  const content = [
    {
      type: "image",
      source: { type: "base64", media_type: "image/jpeg", data: await toBase64(foodImage) }
    }
  ];

  if (labelImage) {
    content.push({
      type: "image",
      source: { type: "base64", media_type: "image/jpeg", data: await toBase64(labelImage) }
    });
  }

  content.push({
    type: "text",
    text: labelImage ? PROMPT_WITH_LABEL : PROMPT_WITHOUT_LABEL
  });

  const response = await claude.messages.create({
    model: "claude-sonnet-4-5",
    max_tokens: 1024,
    messages: [{ role: "user", content }],
    output_config: {
      format: { type: "json_schema", schema: FoodRecognitionSchema }
    }
  });

  // Response is guaranteed to match schema
  return JSON.parse(response.content[0].text);
}
```

---

## 9. Testing and Validation

### 9.1 Test Image Categories

Prepare test images covering:

| Category | Examples | Expected Challenges |
|----------|----------|---------------------|
| Simple meals | Toast, eggs, cereal | Portion estimation |
| Complex meals | Mixed plates, curries | Item identification |
| Packaged foods | Chips, bars, drinks | Label integration |
| Australian foods | Meat pies, Tim Tams | Regional recognition |
| Drinks | Beer, wine, coffee | Volume estimation |
| Poor lighting | Dim restaurants | Confidence reduction |
| Partial visibility | Half-eaten meals | Estimation accuracy |

### 9.2 Accuracy Metrics

Per specification.md section 10.1:

| Metric | Target |
|--------|--------|
| Recognition accuracy | >= 70% of meals return usable estimates |
| Acceptance rate | >= 60% of suggestions accepted without major modification |
| Processing time | < 10 seconds |

### 9.3 Validation Checklist

- [ ] JSON output always valid and parseable
- [ ] All required fields present
- [ ] Macro values are non-negative numbers
- [ ] Confidence scores between 0 and 1
- [ ] servingsEstimated only populated when label provided
- [ ] totalMacros matches sum of item macros
- [ ] Notes field provides useful context

---

## 10. Future Enhancements

### 10.1 Drink Recognition

Extend prompts to handle alcohol and beverages:
- Volume estimation (pint, glass, bottle)
- ABV estimation for alcoholic drinks
- Carbohydrate content for mixers and sugary drinks

### 10.2 Learning from Corrections

Track user edits to AI suggestions:
- Store original vs. accepted values
- Identify systematic over/under-estimation patterns
- Use for prompt refinement

### 10.3 Local Model Support

Per specification FR-15, investigate:
- On-device food recognition models
- Offline capability for airplane/connectivity-limited use
- Hybrid approach (local identification, cloud macro lookup)

---

## Revision History

| Date | Version | Author | Changes |
|------|---------|--------|---------|
| 2026-02-05 | 1.0 | Claude | Initial prompt design based on research |
