# MeData

A native iOS application that estimates the carbohydrate content of a meal from one or two photographs using on-device computer vision and a bundled food-composition database.

## Project structure

| Path | Description |
|---|---|
| `App/` | iOS SwiftUI application target |
| `MedataCore/` | Swift Package — platform-neutral pipeline modules |
| `HarnessCore/` | Offline test-set harness library |
| `HarnessCLI/` | Command-line accuracy / calibration runner |
| `specs/research/` | Requirements, design, and task specification |
| `tools/` | Development and CI scripts |
| `static/` | Brand source assets (favicons / icons), inputs to per-target icon generation |

## Building

```sh
swift build
swift test
```

## CI scripts

```sh
bash tools/check_spelling.sh   # Irish/British English spelling linter (Req 19.2)
```
