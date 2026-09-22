sed -i 's|http://archive.ubuntu.com/ubuntu/|https://mirrors.cernet.edu.cn/ubuntu/|g' /etc/apt/sources.list
apt-get install --reinstall ca-certificates
apt update

apt-get install git repo python2.7 python3.10 -y

update-alternatives --install /usr/bin/python python /usr/bin/python2.7 1
update-alternatives --install /usr/bin/python python /usr/bin/python3.10 2
update-alternatives --config python # select 1

ln -s /usr/bin/python /usr/bin/python2

.repo/repo/repo sync -l -j64

apt-get install git xxd ssh make time file sudo gcc rsync bzip2 libssl-dev liblz4-tool expect g++ patchelf chrpath gawk texinfo chrpath diffstat binfmt-support qemu-user-static live-build bison flex fakeroot cmake gcc-multilib g++-multilib unzip device-tree-compiler ncurses-dev whiptail bc -y

./build.sh lunch # select 3
export RK_ROOTFS_SYSTEM=buildroot

./build.sh all

########

tar -xzf buildroot_dl_4c7c9df616fb.tar.gz
tar -xzf tspi_linux_sdk_repo_20240131.tar.gz


# busybox-initramfs distro-info initramfs-tools initramfs-tools-bin initramfs-tools-core klibc-utils kmod libklibc linux-base systemd-hwe-hwdb udev zstd

docker run --privileged -v /proc/sys/fs/binfmt_misc:/proc/sys/fs/binfmt_misc -it --rm -v ./.repo:/root/.repo ubuntu:tspi bash

##

修改下面文件:
./bulldroot/output/rockchip_rk3566/build/host-squashfs-xxxx/squashfs-tools/mksquashfs.h

mksquashfs.h 文件 136 行 前面增加 extern
删除 mksquashfs.o, 