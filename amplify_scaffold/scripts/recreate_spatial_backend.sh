#!/usr/bin/env bash
# Wrapper to run the expect automation and then push the Amplify stack.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v amplify >/dev/null 2>&1; then
  echo "ERROR: amplify CLI not found in PATH. Install it with 'npm i -g @aws-amplify/cli' and configure credentials."
  exit 2
fi

if ! command -v expect >/dev/null 2>&1; then
  echo "ERROR: expect not found. Install it (on Ubuntu: sudo apt update && sudo apt install -y expect)."
  exit 2
fi

echo "Running Amplify automation expect script..."
expect "$SCRIPT_DIR/recreate_spatial_backend.expect"

echo "Now running 'amplify push --yes' to provision resources in the cloud."
amplify push --yes

echo "Done. If amplify push succeeded, amplifyconfiguration.dart and backend resources should be generated." 
