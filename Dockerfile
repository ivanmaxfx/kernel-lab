# ============================
# Stage 1 — builder
# ============================
FROM ubuntu:22.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && apt install -y \
    build-essential bc bison flex libssl-dev libelf-dev \
    cpio gzip make wget xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# -------------------------------
# Extract kernel
# -------------------------------
RUN wget https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.10.201.tar.xz \
    && tar -xf linux-5.10.201.tar.xz \
    && mv linux-5.10.201 linux


# -------------------------------
# Build static BusyBox
# -------------------------------
COPY busybox-1.36.1.tar.bz2 .

RUN tar -xf busybox-1.36.1.tar.bz2 && \
    cd busybox-1.36.1 && \
    make defconfig && \
    sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config && \
    make -j$(nproc) && \
    make install

# -------------------------------
# Create initramfs directory tree
# -------------------------------
RUN mkdir -p /workspace/initramfs
RUN mkdir -p /workspace/initramfs/bin
RUN mkdir -p /workspace/initramfs/sbin
RUN mkdir -p /workspace/initramfs/dev
RUN mkdir -p /workspace/initramfs/proc
RUN mkdir -p /workspace/initramfs/sys
RUN mkdir -p /workspace/initramfs/lib/modules

# Copy BusyBox installation
RUN cp -a /workspace/busybox-1.36.1/_install/* /workspace/initramfs/

# Symlink sh → busybox
RUN ln -sf /bin/busybox /workspace/initramfs/bin/sh

# Create character devices
RUN mknod -m 600 /workspace/initramfs/dev/console c 5 1 || true
RUN mknod -m 666 /workspace/initramfs/dev/null c 1 3 || true

# -------------------------------
# Create /init script
# -------------------------------
RUN printf '#!/bin/sh\n\
mount -t proc proc /proc\n\
mount -t sysfs sysfs /sys\n\
echo "INIT STARTED"\n\
insmod /lib/modules/*.ko 2>/insmod.err\n\
dmesg > /dmesg.log\n\
echo "--- insmod.err ---"\n\
cat /insmod.err\n\
echo "-------------------"\n\
if grep -q "hello" /dmesg.log; then\n\
    echo "MODULE LOAD OK"\n\
    poweroff -f\n\
else\n\
    echo "MODULE LOAD FAILED"\n\
    poweroff -f\n\
fi\n' > /workspace/initramfs/init

RUN chmod +x /workspace/initramfs/init

# -------------------------------
# Configure kernel to embed initramfs
# -------------------------------
WORKDIR /workspace/linux
RUN make defconfig

RUN scripts/config --enable CONFIG_BLK_DEV_INITRD
RUN scripts/config --set-str CONFIG_INITRAMFS_SOURCE "../initramfs"
RUN scripts/config --set-val CONFIG_INITRAMFS_ROOT_UID 0
RUN scripts/config --set-val CONFIG_INITRAMFS_ROOT_GID 0

RUN make -j$(nproc)

# -------------------------------
# Build student module
# -------------------------------
WORKDIR /workspace
COPY student-module student-module
WORKDIR /workspace/student-module

RUN make -C /workspace/linux M=$(pwd) modules

RUN cp *.ko /workspace/initramfs/lib/modules/

# -------------------------------
# Pack initramfs (NOTE: kernel already embeds it,
# but keeping a standalone copy is useful)
# -------------------------------
WORKDIR /workspace
RUN cd initramfs && \
    find . -print0 | cpio --null -ov --format=newc | gzip -9 > /workspace/initramfs.cpio.gz


# ============================
# Stage 2 — runtime
# ============================
FROM ubuntu:22.04
RUN apt update && apt install -y qemu-system-x86 && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# Kernel + initramfs from builder
COPY --from=builder /workspace/linux/arch/x86/boot/bzImage .
COPY --from=builder /workspace/initramfs.cpio.gz .

# Create QEMU run script
RUN printf '#!/bin/sh\n\
echo "==== Booting kernel ===="\n\
qemu-system-x86_64 \\\n\
  -kernel /workspace/bzImage \\\n\
  -initrd /workspace/initramfs.cpio.gz \\\n\
  -nographic \\\n\
  -no-reboot \\\n\
  -append "console=ttyS0"\n' \
> /workspace/run-qemu.sh

RUN chmod +x /workspace/run-qemu.sh

ENTRYPOINT ["/workspace/run-qemu.sh"]
