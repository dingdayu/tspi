# builder/Dockerfile
# ---------------------------------------------------------------------------
# Ubuntu 22.04 build sandbox for the LCKFB TaishanPi RK3566 Kernel 6.1 SDK.
#
# The multi-GB SDK is NOT copied into this image. The repository is
# bind-mounted at /work (see builder/README.md and scripts/host/enter-builder.sh).
#
# Python policy (AGENTS.md section 11, explicit correction):
#   * default `python` MUST resolve to Python 3.
#   * Python 2.7 is installed only for legacy vendor scripts and must be
#     invoked explicitly as `python2.7` / `python2`.
# ---------------------------------------------------------------------------
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# --- Base packages + vendor build dependencies -----------------------------
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && sed -i 's|http://archive.ubuntu.com/ubuntu/|https://mirrors.cernet.edu.cn/ubuntu/|g' /etc/apt/sources.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        # VCS / SDK tooling
        git git-lfs repo rsync \
        # build essentials
        build-essential gcc g++ make cmake pkg-config \
        gcc-multilib g++-multilib \
        # kernel / dtc / kbuild deps
        bison flex bc libssl-dev libelf-dev libncurses-dev \
        libgmp-dev libmpfr-dev libmpc-dev \
        device-tree-compiler \
        liblz4-tool lz4 zstd bzip2 unzip xz-utils cpio kmod \
        # rootfs / cross / qemu / chroot
        qemu-user-static binfmt-support fakeroot live-build debootstrap \
        patchelf chrpath \
        # misc vendor-script deps
        python3 python3-pip python-is-python3 python2.7 \
        file time xxd whiptail expect sudo locales \
        gawk texinfo diffstat gettext patch \
        curl wget openssh-client \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# --- Python policy: default `python` -> Python 3 ---------------------------
# python-is-python3 provides /usr/bin/python -> python3. Legacy SDK scripts
# that genuinely need Python 2 must call `python2.7` explicitly.
RUN python --version && python2.7 --version

# --- Non-root builder user with passwordless sudo --------------------------
ARG BUILDER_UID=1000
ARG BUILDER_GID=1000
RUN groupadd -g "${BUILDER_GID}" builder 2>/dev/null || true \
    && useradd -m -u "${BUILDER_UID}" -g "${BUILDER_GID}" -s /bin/bash builder 2>/dev/null || true \
    && echo 'builder ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/builder \
    && chmod 0440 /etc/sudoers.d/builder

# --- Optional ccache (correctness must never depend on it) -----------------
ARG ENABLE_CCACHE=0
RUN if [ "${ENABLE_CCACHE}" = "1" ]; then \
      apt-get update && apt-get install -y --no-install-recommends ccache \
      && rm -rf /var/lib/apt/lists/* ; \
    fi

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
