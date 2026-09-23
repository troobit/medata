#!/usr/bin/env bash
# Regenerate Swift sources from .proto schemas.
# Usage: bash MedataCore/Sources/PortableContracts/Schemas/generate.sh
# Requires: protoc (>= 25), protoc-gen-swift (>= 1.27).
set -euo pipefail

SCHEMA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATED_DIR="$SCHEMA_DIR/../Generated"
mkdir -p "$GENERATED_DIR"

protoc \
    --proto_path="$SCHEMA_DIR" \
    --swift_out="$GENERATED_DIR" \
    --swift_opt=Visibility=Public \
    "$SCHEMA_DIR"/*.proto

echo "Regenerated $(ls "$GENERATED_DIR"/*.pb.swift | wc -l) Swift files."
