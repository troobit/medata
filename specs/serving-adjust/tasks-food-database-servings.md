---
references:
    - prd.md
---
# Serving-based portion adjustment — Food database servings

## Generator servings table

- [x] 1. Write failing generator tests for solid_servings <!-- id:v9970ip -->
  - Schema: solid_servings(class_id TEXT PRIMARY KEY, unit_singular, unit_plural, grams_per_unit REAL, step REAL, source TEXT)
  - Coverage rule: every non-liquid foods class has a row or is deliberately absent; orphan class_id (not in foods) fails generation
  - Follow existing test layout under tools/food_db/tests/

- [x] 2. Implement solid_servings in generate.py and regenerate committed DBs <!-- id:v9970iq -->
  - Seed weights + per-row source citations exactly per PRD Req 1 (BDA sheet; Crawley rows carry 'unverified figure' provenance)
  - Mirror the liquid_servings precedent; do not touch beta or composition columns
  - Regenerate and commit cofid_db.sqlite + afcd_db.sqlite under MedataCore/Sources/Foods/Resources/
  - Blocked-by: v9970ip (Write failing generator tests for solid_servings)

## Swift lookup

- [x] 3. Write failing Foods test for the serving lookup <!-- id:v9970ir -->
  - Executed MedataCore suite: potato_boiled resolves to (unit, grams, step); water (liquid) returns nil

- [x] 4. Implement FoodDatabase solid-serving lookup <!-- id:v9970is -->
  - Expose (unitSingular, unitPlural, gramsPerUnit, step) per class id from solid_servings
  - make test green (both totals), make spell clean
  - Blocked-by: v9970iq (Implement solid_servings in generate.py and regenerate committed DBs), v9970ir (Write failing Foods test for the serving lookup)
