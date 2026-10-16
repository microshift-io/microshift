# TopoLVM VG_NAME and SPARE_GB A/B Test Plan

## Overview

Comprehensive end-to-end test suite for validating TopoLVM volume group configuration through the MicroShift build and deployment pipeline.

## What This Tests

The test suite validates all permutations of `VG_NAME` and `SPARE_GB` configuration parameters across three pipeline stages:

1. **SRPM build** - generates initial lvmd.yaml
2. **Bootc image build** - regenerates lvmd.yaml  
3. **Runtime** - creates actual LVM volume group

## Test Coverage

### Positive Tests (4)
- ✓ Default/Default (VG_NAME=myvg1, SPARE_GB=0)
- ✓ Custom VG, Default Spare (VG_NAME=test-vg-custom, SPARE_GB=0)
- ✓ Default VG, Custom Spare (VG_NAME=myvg1, SPARE_GB=5)
- ✓ Custom/Custom (VG_NAME=test-vg-full, SPARE_GB=10)

### Negative Tests (3)
- ✓ Image/Runtime VG mismatch (should fail gracefully)
- ✓ Missing runtime VG_NAME (should exit with error)
- ✓ SRPM/Image spare mismatch (image should override)

## Prerequisites

### On Test VM (ushift-devel-el98)
- MicroShift upstream repository cloned to `/home/microshift/microshift-io/microshift` (or customize)
- Podman installed and configured
- sudo access available
- All build dependencies installed

### On Development Host
- SSH key-based authentication to test VM
- Bash 4.0+

## Quick Start

```bash
# Run all tests with defaults
./test_topolvm_config.sh

# Customize remote host and directory
REMOTE_HOST=my-test-vm REMOTE_DIR=/path/to/microshift ./test_topolvm_config.sh

# Results saved to timestamped directory
ls -l test-results-*/
```

## Configuration Variables

Set these environment variables to customize test execution:

```bash
# SSH target (default: ushift-devel-el98)
export REMOTE_HOST=ushift-devel-el98

# MicroShift repo path on remote (default: /home/microshift/microshift-io/microshift)
export REMOTE_DIR=/home/microshift/microshift-io/microshift

# Local results directory (default: ./test-results-YYYYMMDD-HHMMSS)
export TEST_RESULTS_DIR=./my-test-results
```

## Test Execution Flow

Each test follows this sequence:

1. **Environment Cleanup**
   - Remove any existing containers
   - Delete test volume groups
   - Detach loopback devices
   - Verify clean state

2. **Build Sequence**
   - Build SRPM with specified VG_NAME/SPARE_GB
   - Build RPM from SRPM
   - Build bootc image with specified VG_NAME/SPARE_GB

3. **Deployment**
   - Create cluster with specified VG_NAME
   - Wait for service ready (5min timeout)
   - Wait for service healthy (15min timeout)

4. **Verification**
   - Verify lvmd.yaml config matches expected values
   - Verify actual host VG matches config
   - Verify TopoLVM pods running
   - Test volume provisioning (create PVC, verify LV created)

5. **Cleanup**
   - Remove cluster and LVM backend
   - Verify clean state for next test

## Verification Steps

### lvmd.yaml Configuration
- Checks volume-group name matches expected value
- Checks spare-gb matches expected value

### Host Volume Group
- Verifies VG exists with correct name
- Verifies config VG matches actual host VG

### TopoLVM Components
- All pods in topolvm-system namespace running
- Pods pass readiness checks
- MicroShift healthcheck passes
- StorageClass is default

### Volume Provisioning
- Creates test PVC (100Mi)
- PVC binds successfully within 60s
- Logical volume appears in `lvs` output
- Cleanup removes PVC

## Diagnostic Collection

On test failure, diagnostics are automatically collected:

```
test-results-<timestamp>/<test-name>/
├── vgs.txt              # Volume group status
├── lvs.txt              # Logical volume status  
├── pvs.txt              # Physical volume status
├── lsblk.txt            # Block device listing
├── losetup.txt          # Loopback device status
├── podman-ps.txt        # Container status
├── podman-images.txt    # Image listing
├── microshift.log       # MicroShift service logs
├── lvmd.yaml            # TopoLVM lvmd config
├── lvmd.log             # TopoLVM lvmd daemon logs
├── controller.log       # TopoLVM controller logs
├── pods.txt             # All pod status
└── events.txt           # Kubernetes events
```

## Expected Results

### Positive Tests
All verification steps should pass:
- Clean environment verified
- Build completes successfully
- Cluster starts and reaches healthy state
- Config matches expected values
- Volume provisioning succeeds
- Cleanup successful

### Negative Test 5 (VG Mismatch)
- Build succeeds
- Cluster starts
- Config has image VG, host has runtime VG
- Volume provisioning **fails**
- lvmd logs show VG not found errors

### Negative Test 6 (Missing Runtime VG)
- Build succeeds
- `make run` **fails immediately**
- Error message: "VG_NAME is required"
- No cluster created

### Negative Test 7 (Spare Mismatch)
- Build succeeds
- lvmd.yaml has **image** SPARE_GB value (not SRPM)
- Cluster functions normally
- Volume provisioning succeeds

## Manual Test Execution

To run individual test cases manually on the VM:

```bash
# SSH to test VM
ssh ushift-devel-el98

# Navigate to repo
cd /home/microshift/microshift-io/microshift

# Example: Test 1 (Default/Default)
make clean-all VG_NAME=myvg1
make srpm VG_NAME=myvg1 SPARE_GB=0
make rpm
make image VG_NAME=myvg1 SPARE_GB=0
VG_NAME=myvg1 make run
VG_NAME=myvg1 make run-ready
VG_NAME=myvg1 make run-healthy

# Verify config
sudo podman exec microshift-okd-1 cat /etc/topolvm/lvmd.yaml

# Verify VG
sudo vgs

# Test provisioning
VG_NAME=myvg1 make env CMD='kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi
  storageClassName: topolvm-provisioner
EOF'

# Check PVC status
VG_NAME=myvg1 make env CMD='kubectl get pvc test-pvc'

# Cleanup
VG_NAME=myvg1 make env CMD='kubectl delete pvc test-pvc'
make clean-all VG_NAME=myvg1
```

## Troubleshooting

### SSH Connection Issues
```bash
# Verify SSH access
ssh ushift-devel-el98 'echo SSH works'

# Check SSH key
ssh-add -l
```

### Build Failures
```bash
# Check remote disk space
ssh ushift-devel-el98 'df -h'

# Check podman storage
ssh ushift-devel-el98 'sudo podman system df'

# Clean up podman storage
ssh ushift-devel-el98 'sudo podman system prune -a -f'
```

### Cleanup Issues
```bash
# Manual cleanup on remote
ssh ushift-devel-el98 'bash -s' <<'EOF'
sudo podman stop microshift-okd-1 || true
sudo podman rm -f microshift-okd-1 || true
sudo lvremove -y myvg1 || true
sudo vgremove -y myvg1 || true
sudo losetup -D
sudo rm -rf /var/lib/microshift-okd
EOF
```

### Test Hangs
- Service ready timeout: 5 minutes (may indicate deployment issues)
- Service healthy timeout: 15 minutes (greenboot checks)
- PVC bind timeout: 60 seconds (may indicate TopoLVM issues)

Check diagnostics in test results directory for details.

## Implementation Details

The test automation script (`test_topolvm_config.sh`) implements the test plan from [the detailed plan document](.claude/plans/generate-a-test-plan-witty-mist.md).

Key features:
- Color-coded output (green=pass, red=fail, yellow=info)
- Automatic diagnostic collection on failure
- Comprehensive verification at each stage
- Clean environment guarantee between tests
- Parallel-safe (tests run sequentially)

## CI Integration

To integrate into CI pipeline:

```yaml
- name: Run TopoLVM Config Tests
  run: |
    export REMOTE_HOST=test-vm-runner
    export REMOTE_DIR=/workspace/microshift
    ./test_topolvm_config.sh
```

Set `REMOTE_HOST` to match your CI runner environment.

## Related Documentation

- [src/topolvm/README.md](src/topolvm/README.md) - TopoLVM integration documentation
- [CLAUDE.md](CLAUDE.md) - Project build system architecture
- [.claude/plans/generate-a-test-plan-witty-mist.md](.claude/plans/generate-a-test-plan-witty-mist.md) - Detailed test plan

## Success Criteria

✓ All 4 positive tests pass all verification steps  
✓ All 3 negative tests fail in the expected manner  
✓ Total: 7/7 tests passing

## Time Estimate

- Per test: ~20-30 minutes (build + deploy + verify)
- Full suite: ~2.5-3.5 hours (sequential execution)
