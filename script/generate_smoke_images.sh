#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
swift script/generate_smoke_images.swift "${1:-build/SmokeImages}"
