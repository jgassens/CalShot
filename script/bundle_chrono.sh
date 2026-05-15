#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -d node_modules ]]; then
  npm ci
fi

npm run bundle:chrono

if [[ -f node_modules/chrono-node/LICENSE.txt ]]; then
  mkdir -p Resources/Licenses
  cp node_modules/chrono-node/LICENSE.txt Resources/Licenses/chrono-node-MIT.txt
fi

echo "Wrote Resources/chrono.bundle.js"

