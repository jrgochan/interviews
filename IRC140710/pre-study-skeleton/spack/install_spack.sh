#!/usr/bin/env bash
set -euo pipefail

# Install Spack
if [ ! -d spack/spack ]; then
    git clone https://github.com/spack/spack.git spack/spack
fi

# Source Spack environment
source spack/spack/share/spack/setup-env.sh

# Add a default configuration (optional)
# spack config add config:build_system:build_jobs: 4

echo "Spack installed.  Run 'source spack/spack/share/spack/setup-env.sh' to activate."
