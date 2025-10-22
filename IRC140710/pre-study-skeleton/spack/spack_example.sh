#!/usr/bin/env bash
set -euo pipefail

# Source Spack environment (assuming Spack is installed in spack/spack)
source spack/spack/share/spack/setup-env.sh

# Install a package (e.g., fftw)
spack install fftw

# Load the environment for the installed package
spack load fftw

# Run a simple command to verify the installation
which fftw-wisdom

echo "Spack example complete. fftw is installed and loaded."
