---
references:
    - requirements.md
---
# Datagen Test Data Specification

## R1: Blood Glucose Data Generation

- [x] 1. Investigate: Review existing data models and UI expectations for blood glucose

- [x] 2. Implement: Generate 1 month of 5-minute interval BG readings in mmol/L with stochastic T1 variation

- [x] 3. Verify: Confirm BG data covers 1 month at 5-min intervals with realistic T1 ranges

## R2: Insulin Data (Basal & Bolus)

- [ ] 4. Investigate: Review insulin data model for basal and bolus entries

- [ ] 5. Implement: Generate basal shots (7am & 7pm, 15 units each)

- [ ] 6. Implement: Generate bolus shots for meals, liquor, and snacks

- [ ] 7. Verify: Confirm insulin data follows specified schedule and dosing

## R3: Exercise Data Generation

- [ ] 8. Investigate: Review exercise data model and activity types

- [ ] 9. Implement: Generate swim activities (1hr, high intensity)

- [ ] 10. Implement: Generate cycle activities (20min, medium intensity)

- [ ] 11. Implement: Generate walk activities (40min, low intensity)

- [ ] 12. Verify: Confirm exercise data includes all activity types with correct durations/intensities

## R4: Script & Data Freshness

- [ ] 13. Investigate: Determine output format and storage location for generated data

- [ ] 14. Implement: Create script that generates data ending a few minutes before current time

- [ ] 15. Implement: Add stochastic variation to ensure data differs on each run

- [ ] 16. Verify: Confirm script produces fresh, varied data suitable for local dev
