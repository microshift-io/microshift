#!/bin/bash

truncate --size=5G /tmp/lvmdisk
losetup -f /tmp/lvmdisk
device_name=$(losetup -j /tmp/lvmdisk | cut -d: -f1)
vgcreate -f -y myvg1 ${device_name}
lvcreate -T myvg1/thinpool -L 3G