#!/bin/bash
set -euo pipefail

# Generate EdDSA keys for Sparkle signing
# Run this ONCE, save the public key to project.yml SUPublicEDKey

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Generating Sparkle EdDSA signing keys..."
echo ""

# Find Sparkle's generate_keys tool in the SPM checkout
SPARKLE_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "generate_keys" -path "*/Sparkle/bin/*" 2>/dev/null | head -1)

if [ -z "$SPARKLE_PATH" ]; then
    echo "Sparkle generate_keys not found in DerivedData."
    echo "Build the Xcode project first, then re-run this script."
    echo ""
    echo "Alternative: generate keys manually:"
    echo "  1. Download Sparkle from https://github.com/sparkle-project/Sparkle/releases"
    echo "  2. Run: ./bin/generate_keys"
    echo "  3. Save the public key to project.yml -> SUPublicEDKey"
    exit 1
fi

"$SPARKLE_PATH"

echo ""
echo "IMPORTANT: Copy the PUBLIC key and set it as SUPublicEDKey in project.yml"
echo "The private key is stored in your Keychain automatically by Sparkle."
