#!/usr/bin/env bash
set -euo pipefail
BS=${BS:-1M}
COUNT=${COUNT:-2048}
FILE=${FILE:-testfile.dd}

# Write
dd if=/dev/zero of="$FILE" bs="$BS" count="$COUNT" oflag=direct status=progress
# Read
dd if="$FILE" of=/dev/null bs="$BS" iflag=direct status=progress
