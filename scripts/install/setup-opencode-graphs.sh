#!/usr/bin/env bash
set -euo pipefail

# OpenCode AI Runtime Bootstrap
# Run this on every fresh clone to configure AI tooling locally.
# All generated/config files are gitignored.

bash <(curl -fsSL "https://raw.githubusercontent.com/DuckKota/OpenCode-Graphify-CRG-Setup/refs/heads/main/scripts/install/common.sh")
