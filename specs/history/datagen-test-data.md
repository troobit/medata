# Datagen Test Data

**Branch:** `datagen`

## Overview

Minimal hardcoded test data generation for UI development. This spec created static seed data for testing the application interface without requiring real user data or complex data generation logic.

## Implementation Summary

Created simple, deterministic test data:

- Hardcoded data arrays with no dynamic generation or randomisation
- Blood glucose readings for UI chart testing
- Insulin entries (basal and bolus) for logging display
- Exercise activities for activity tracking UI
- Backend seed script for direct database loading

## Features Implemented

### Hardcoded Data Arrays

- Blood glucose: ~50 readings ranging from 4-12 mmol/L
- Timestamps: Spanning several days with 5-minute intervals
- Insulin basal: Multiple entries at 15 units
- Insulin bolus: Variable doses for meal coverage
- Exercise: 2-3 sample activities with different types and durations

### Backend Seed Script

- Script to load seed data directly into the database
- No frontend input required
- No date adjustment or user interaction
- Deterministic output for consistent UI testing

## Files Changed

### Seed Data (Added)

- `scripts/seed-data.ts` - Hardcoded data arrays
- `scripts/seed.ts` - Database seeding script

## Scope Limitations

Explicitly out of scope for this spec:

- Dynamic data generation
- Stochastic variation or randomisation
- Regression analysis or modelling
- Frontend data input interfaces
- Date adjustment logic

## Design Decisions

- **Hardcoded over generated**: Ensures deterministic, reproducible test data
- **Minimal dataset**: ~50 BG readings sufficient for UI testing without performance concerns
- **Backend-only loading**: Avoids complexity of frontend seed interfaces
