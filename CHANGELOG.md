# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial SvelteKit project scaffold with Svelte 5 and TypeScript strict mode
- Tailwind CSS 4.x configuration with brand colours (#63ff00 accent, #064e3b background, #0a0a0a primary)
- PWA manifest.json with app icons and theme colours
- app.html configured with favicons, manifest link, and theme-color meta tags
- AppShell layout component with header displaying MeData logo
- Home page with action buttons (Capture Meal, Manual Entry, From Preset) and empty logbook placeholder
- .env.example with required environment variable templates (ANTHROPIC_API_KEY, AZURE_COSMOS_CONNECTION_STRING, AZURE_BLOB_STORAGE_URL)
