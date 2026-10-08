#!/bin/bash
set -euo pipefail

output_file="${1:?output file is required}"
vg_name="${2:?volume group name is required}"
source_file="${3:-}"

install -d -m 0755 "$(dirname "${output_file}")"

if [ -n "${source_file}" ]; then
    install -m 0644 "${source_file}" "${output_file}"
    exit 0
fi

cat >"${output_file}" <<EOF
socket-name: /run/topolvm/lvmd.sock
device-classes:
  - default: true
    name: ssd
    spare-gb: 0
    volume-group: ${vg_name}
EOF
