#!/bin/bash

    cat > /etc/microshift/config.yaml <<EOF
storage:
    driver: "none"
telemetry:
    status: "Disabled"
EOF

systemctl enable microshift