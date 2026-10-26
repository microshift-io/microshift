#!/bin/bash
set -euo pipefail

output_file="${1:?output file is required}"
vg_name="${2:?volume group name is required}"
spare_gb="${3:-0}"

install -d -m 0755 "$(dirname "${output_file}")"

cat >"${output_file}" <<EOF
socket-name: /run/topolvm/lvmd.sock
device-classes:
  - default: true
    name: ssd
    spare-gb: ${spare_gb}
    volume-group: ${vg_name}
EOF
