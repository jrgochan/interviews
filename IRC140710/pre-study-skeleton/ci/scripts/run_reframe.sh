#!/usr/bin/env bash
set -euo pipefail
reframe -C reframe/reframe_settings.py -c reframe/tests -r --system local:cpu
