#!/bin/bash
set -euo pipefail

cat > /etc/microshift/config.yaml <<EOF
storage:
    driver: "none"
EOF

systemctl enable microshift
