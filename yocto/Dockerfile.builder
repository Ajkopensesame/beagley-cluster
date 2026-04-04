FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    bc \
    bison \
    build-essential \
    ca-certificates \
    chrpath \
    cpio \
    curl \
    debianutils \
    diffstat \
    file \
    flex \
    gawk \
    gcc \
    git \
    iputils-ping \
    libegl1-mesa \
    libsdl1.2-dev \
    locales \
    lz4 \
    python3 \
    python3-git \
    python3-jinja2 \
    python3-pexpect \
    python3-pip \
    rsync \
    socat \
    sudo \
    texinfo \
    unzip \
    wget \
    xterm \
    xz-utils \
    zstd \
 && locale-gen en_US.UTF-8 \
 && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash builder \
 && echo 'builder ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/builder \
 && chmod 0440 /etc/sudoers.d/builder

USER builder
WORKDIR /workspace

CMD ["bash"]
