Generate minimal test data for UI development.

1. Hardcoded data arrays only - no dynamic generation, no stochastic variation
2. Blood glucose: array of ~50 readings (mmol/L values between 4-12)
3. Times: array of timestamps spanning a few days, 5-minute intervals
4. Insulin: handful of basal entries (15 units), handful of bolus entries (varies)
5. Exercise: 2-3 sample activities
6. Data loads directly into DB via backend seed script
7. No frontend input, no date adjustment, no randomisation
8. Scope: UI testing only - regression analysis is explicitly out of scope
