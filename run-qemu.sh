#!/bin/sh
echo "==== Booting kernel with initramfs ===="

qemu-system-x86_64 \
  -kernel /workspace/bzImage \
  -initrd /workspace/initramfs.cpio.gz \
  -nographic \
  -append "console=ttyS0"
