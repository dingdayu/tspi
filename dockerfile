FROM ubuntu:22.04

# 设置环境变量以避免交互式提示
ENV DEBIAN_FRONTEND=noninteractive  TZ=Asia/Shanghai

RUN apt update \
	&& sed -i 's|http://archive.ubuntu.com/ubuntu/|https://mirrors.cernet.edu.cn/ubuntu/|g' /etc/apt/sources.list \
	&& apt-get install --reinstall ca-certificates -y \
        && apt update \
        && apt-get install -y git rsync bzip2 repo python2.7 python3.10 ssh make time file sudo gcc libssl-dev liblz4-tool expect g++ patchelf chrpath \
	gawk texinfo diffstat binfmt-support xxd qemu-user-static live-build bison flex fakeroot cmake gcc-multilib g++-multilib unzip device-tree-compiler ncurses-dev whiptail bc tzdata \
	&& apt-get clean && rm -rf /var/lib/apt/lists/*
	

# 设置 Python 2.7 和 Python 3.10 的 alternatives
RUN update-alternatives --install /usr/bin/python python /usr/bin/python2.7 1 && \
    update-alternatives --install /usr/bin/python python /usr/bin/python3.10 2

# 设置默认的 Python 版本为 Python 2.7
RUN echo 1 | update-alternatives --config python && \
	ln -s /usr/bin/python /usr/bin/python2


# 