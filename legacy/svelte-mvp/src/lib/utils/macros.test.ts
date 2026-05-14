/**
 * Property-based tests for macro calculation utility.
 * Per design section 6.3
 * Test-first: these tests are written before the implementation.
 */
import { describe, it, expect } from "vitest";
import * as fc from "fast-check";
import { sumMacros } from "./macros.js";

describe("sumMacros", () => {
  // Property: Sum is always non-negative
  it("always returns non-negative totals", () => {
    fc.assert(
      fc.property(
        fc.array(
          fc.record({
            name: fc.string({ minLength: 1 }),
            carbs: fc.nat(),
            protein: fc.nat(),
            fat: fc.nat(),
          }),
        ),
        (items) => {
          const total = sumMacros(items);
          return total.carbs >= 0 && total.protein >= 0 && total.fat >= 0;
        },
      ),
    );
  });

  // Property: Empty array returns zeros
  it("returns zeros for empty array", () => {
    expect(sumMacros([])).toEqual({ carbs: 0, protein: 0, fat: 0 });
  });

  // Property: Single item returns same values
  it("single item returns same values", () => {
    fc.assert(
      fc.property(
        fc.record({
          name: fc.string({ minLength: 1 }),
          carbs: fc.nat(),
          protein: fc.nat(),
          fat: fc.nat(),
        }),
        (item) => {
          const total = sumMacros([item]);
          return (
            total.carbs === item.carbs &&
            total.protein === item.protein &&
            total.fat === item.fat
          );
        },
      ),
    );
  });

  // Property: Order doesn't matter (commutativity of addition)
  it("sum is commutative - order does not affect result", () => {
    fc.assert(
      fc.property(
        fc.array(
          fc.record({
            name: fc.string({ minLength: 1 }),
            carbs: fc.nat(),
            protein: fc.nat(),
            fat: fc.nat(),
          }),
          { minLength: 2, maxLength: 10 },
        ),
        (items) => {
          const total1 = sumMacros(items);
          const total2 = sumMacros([...items].reverse());
          return (
            total1.carbs === total2.carbs &&
            total1.protein === total2.protein &&
            total1.fat === total2.fat
          );
        },
      ),
    );
  });

  // Property: Adding an item with zero macros doesn't change the sum
  it("adding zero-macro item does not change sum", () => {
    fc.assert(
      fc.property(
        fc.array(
          fc.record({
            name: fc.string({ minLength: 1 }),
            carbs: fc.nat(),
            protein: fc.nat(),
            fat: fc.nat(),
          }),
        ),
        (items) => {
          const total1 = sumMacros(items);
          const total2 = sumMacros([
            ...items,
            { name: "zero", carbs: 0, protein: 0, fat: 0 },
          ]);
          return (
            total1.carbs === total2.carbs &&
            total1.protein === total2.protein &&
            total1.fat === total2.fat
          );
        },
      ),
    );
  });

  // Property: Sum of two arrays equals sum of concatenated array
  it("sum of concatenated arrays equals sum of individual sums", () => {
    fc.assert(
      fc.property(
        fc.array(
          fc.record({
            name: fc.string({ minLength: 1 }),
            carbs: fc.nat(),
            protein: fc.nat(),
            fat: fc.nat(),
          }),
        ),
        fc.array(
          fc.record({
            name: fc.string({ minLength: 1 }),
            carbs: fc.nat(),
            protein: fc.nat(),
            fat: fc.nat(),
          }),
        ),
        (items1, items2) => {
          const total1 = sumMacros(items1);
          const total2 = sumMacros(items2);
          const totalCombined = sumMacros([...items1, ...items2]);
          return (
            totalCombined.carbs === total1.carbs + total2.carbs &&
            totalCombined.protein === total1.protein + total2.protein &&
            totalCombined.fat === total1.fat + total2.fat
          );
        },
      ),
    );
  });

  // --- Task 27: Property-based tests using fc.float generators ---

  // Property: sumMacros(items).carbs === sum of all item.carbs (totalCarbs identity)
  it("totalCarbs equals sum of all item.carbs (float values)", () => {
    fc.assert(
      fc.property(
        fc.array(
          fc.record({
            carbs: fc.float({ min: 0, max: 200, noNaN: true }),
            protein: fc.float({ min: 0, max: 200, noNaN: true }),
            fat: fc.float({ min: 0, max: 200, noNaN: true }),
          }),
        ),
        (items) => {
          const result = sumMacros(items);
          const expectedCarbs = items.reduce(
            (sum, item) => sum + item.carbs,
            0,
          );
          return Math.abs(result.carbs - expectedCarbs) < 1e-6;
        },
      ),
    );
  });

  // Property: sumMacros(items).protein === sum of all item.protein
  it("totalProtein equals sum of all item.protein (float values)", () => {
    fc.assert(
      fc.property(
        fc.array(
          fc.record({
            carbs: fc.float({ min: 0, max: 200, noNaN: true }),
            protein: fc.float({ min: 0, max: 200, noNaN: true }),
            fat: fc.float({ min: 0, max: 200, noNaN: true }),
          }),
        ),
        (items) => {
          const result = sumMacros(items);
          const expectedProtein = items.reduce(
            (sum, item) => sum + item.protein,
            0,
          );
          return Math.abs(result.protein - expectedProtein) < 1e-6;
        },
      ),
    );
  });

  // Property: sumMacros(items).fat === sum of all item.fat
  it("totalFat equals sum of all item.fat (float values)", () => {
    fc.assert(
      fc.property(
        fc.array(
          fc.record({
            carbs: fc.float({ min: 0, max: 200, noNaN: true }),
            protein: fc.float({ min: 0, max: 200, noNaN: true }),
            fat: fc.float({ min: 0, max: 200, noNaN: true }),
          }),
        ),
        (items) => {
          const result = sumMacros(items);
          const expectedFat = items.reduce((sum, item) => sum + item.fat, 0);
          return Math.abs(result.fat - expectedFat) < 1e-6;
        },
      ),
    );
  });

  // Property: sumMacros([]) returns zero totals (float version)
  it("returns zero totals for empty array (float generators context)", () => {
    const result = sumMacros([]);
    expect(result).toEqual({ carbs: 0, protein: 0, fat: 0 });
  });

  // Property: all totals are non-negative when item values are non-negative (float version)
  it("all totals are non-negative when items have non-negative float values", () => {
    fc.assert(
      fc.property(
        fc.array(
          fc.record({
            carbs: fc.float({ min: 0, max: 200, noNaN: true }),
            protein: fc.float({ min: 0, max: 200, noNaN: true }),
            fat: fc.float({ min: 0, max: 200, noNaN: true }),
          }),
        ),
        (items) => {
          const result = sumMacros(items);
          return result.carbs >= 0 && result.protein >= 0 && result.fat >= 0;
        },
      ),
    );
  });

  // Explicit example tests for documentation
  it("calculates correct totals for typical meal", () => {
    const items = [
      { name: "Scrambled Eggs", carbs: 2, protein: 13, fat: 11 },
      { name: "Toast", carbs: 25, protein: 4, fat: 2 },
    ];
    const total = sumMacros(items);
    expect(total).toEqual({ carbs: 27, protein: 17, fat: 13 });
  });
});
