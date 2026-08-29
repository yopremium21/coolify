#!/usr/bin/env bash
set -Eeuo pipefail
curl -fsSL https://raw.githubusercontent.com/yopremium21/coolify/main/install.sh | bash -s -- "$@"
