ARG BASE_OS=debian

# Specify versions of Erlang, Elixir, and base OS.
# Choose a combination supported by https://hub.docker.com/r/hexpm/elixir/tags

ARG ELIXIR_VER=1.14.3
ARG OTP_VER=25.2.3
ARG BUILD_OS_VER=bullseye-20230202-slim

# https://docker.debian.net/
# https://hub.docker.com/_/debian
ARG PROD_OS_VER=bullseye-slim

# Use snapshot for consistent dependencies, see https://snapshot.debian.org/
# Needs to be updated manually
ARG SNAPSHOT_VER=20230202

# Docker registry for internal images, e.g. 123.dkr.ecr.ap-northeast-1.amazonaws.com/
# If blank, docker.io will be used. If specified, should have a trailing slash.
ARG REGISTRY=""
# Registry for public images such as debian, alpine, or postgres.
ARG PUBLIC_REGISTRY=""
# Public images may be mirrored into the private registry, with e.g. Skopeo
# ARG PUBLIC_REGISTRY=$REGISTRY

# Base image for build and test
ARG BUILD_BASE_IMAGE_NAME=${PUBLIC_REGISTRY}hexpm/elixir
ARG BUILD_BASE_IMAGE_TAG=${ELIXIR_VER}-erlang-${OTP_VER}-${BASE_OS}-${BUILD_OS_VER}

ARG BUILDROOT_GIT_REPO='https://github.com/buildroot/buildroot.git'
ARG BUILDROOT_TAG='2023.05.x'
ARG BUILDROOT_BOARD='raspberrypi4'
ARG BUILDROOT_DEFCONFIG='raspberrypi4_defconfig'

# App name, used to name directories
ARG APP_NAME=app

# Dir where app is installed
ARG APP_DIR=/app

# OS user for app to run under
# nonroot:x:65532:65532:nonroot:/home/nonroot:/usr/sbin/nologin
# nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
ARG APP_USER=nonroot
# OS group that app runs under
ARG APP_GROUP=$APP_USER
# OS numeric user and group id
ARG APP_USER_ID=65532
ARG APP_GROUP_ID=$APP_USER_ID

ARG LANG=C.UTF-8
# Sometimes Buildroot needs a full locale, e.g. for toolchain based on glibc
# ARG LANG=en_US.utf8

# Elixir release env to build
ARG MIX_ENV=prod

# Name of Elixir release
# This should match mix.exs releases()
ARG RELEASE=prod

# App listen port
ARG APP_PORT=4000

# Allow additional packages to be injected into builds
ARG RUNTIME_PACKAGES=""
ARG DEV_PACKAGES=""

# Create build base image with OS dependencies
FROM ${BUILD_BASE_IMAGE_NAME}:${BUILD_BASE_IMAGE_TAG} AS build-os-deps
    ARG SNAPSHOT_VER
    ARG RUNTIME_PACKAGES

    ARG LANG
    ENV LANG=$LANG

    ARG APP_DIR
    ARG APP_GROUP
    ARG APP_GROUP_ID
    ARG APP_USER
    ARG APP_USER_ID

    # Create OS user and group to run app under
    RUN if ! grep -q "$APP_USER" /etc/passwd; \
        then groupadd -g "$APP_GROUP_ID" "$APP_GROUP" && \
        useradd -l -u "$APP_USER_ID" -g "$APP_GROUP" -s /usr/sbin/nologin "$APP_USER" && \
        rm /var/log/lastlog && rm /var/log/faillog; fi

    # Configure apt caching for use with BuildKit.
    # The default Debian Docker image has special apt config to clear caches,
    # but if we are using --mount=type=cache, then we want to keep the files.
    # https://github.com/debuerreotype/debuerreotype/blob/master/scripts/debuerreotype-minimizing-config
    RUN set -exu && \
        rm -f /etc/apt/apt.conf.d/docker-clean && \
        echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache && \
        echo 'Acquire::CompressionTypes::Order:: "gz";' > /etc/apt/apt.conf.d/99use-gzip-compression

    RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
        --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked \
        --mount=type=cache,id=debconf,target=/var/cache/debconf,sharing=locked \
        set -exu && \
        apt-get update -qq && \
        DEBIAN_FRONTEND=noninteractive \
        apt-get -y install -y -qq --no-install-recommends ca-certificates

    RUN if test -n "$SNAPSHOT_VER" ; then \
            echo "deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/${SNAPSHOT_VER} bullseye main" > /etc/apt/sources.list && \
            echo "deb [check-valid-until=no] https://snapshot.debian.org/archive/debian-security/${SNAPSHOT_VER} bullseye-security main" >> /etc/apt/sources.list && \
            echo "deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/${SNAPSHOT_VER} bullseye-updates main" >> /etc/apt/sources.list; \
        fi

    # Install buildroot build deps
    # https://buildroot.org/downloads/manual/manual.html#requirement
    RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
        --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked \
        --mount=type=cache,id=debconf,target=/var/cache/debconf,sharing=locked \
        set -exu && \
        apt-get update -qq && \
        DEBIAN_FRONTEND=noninteractive \
        apt-get -y install -y -qq --no-install-recommends \
            bash \
            bc \
            binutils \
            bison \
            build-essential \
            bzip2 \
            cpio \
            curl \
            diffutils \
            file \
            findutils \
            flex \
            g++ \
            gcc \
            git \
            gpg \
            gzip \
            # libdevmapper-dev \
            # libfdt-dev \
            libncurses5-dev \
            # libssl-dev \
            # libsystemd-dev \
            locales \
            make \
            # mercurial \
            patch \
            perl \
            python2 \
            rsync \
            sed \
            tar \
            unzip \
            vim \
            wget \
            whois \
        && \
        # Generate locales specified in /etc/locale.gen
        locale-gen && \
        truncate -s 0 /var/log/apt/* && \
        truncate -s 0 /var/log/dpkg.log

    # If LANG=C.UTF-8 is not enough, build full featured locale
    # RUN localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
    # ENV LANG en_US.utf8


# Dev image which mounts code from local filesystem
FROM build-os-deps AS buildroot-dev
    ARG DEV_PACKAGES

    ARG LANG
    ENV LANG=$LANG

    ARG APP_DIR
    ARG APP_GROUP
    ARG APP_NAME
    ARG APP_PORT
    ARG APP_USER

    ARG DEV_PACKAGES

    ARG BUILDROOT_GIT_REPO
    ARG BUILDROOT_TAG
    ARG BUILDROOT_BOARD
    ARG BUILDROOT_DEFCONFIG

    RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
        --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked \
        --mount=type=cache,id=debconf,target=/var/cache/debconf,sharing=locked \
        set -exu && \
        apt-get update -qq && \
        DEBIAN_FRONTEND=noninteractive \
        apt-get -y install -y -qq --no-install-recommends \
            inotify-tools \
            ssh \
            sudo \
            # $DEV_PACKAGES \
        && \
        # https://www.networkworld.com/article/3453032/cleaning-up-with-apt-get.html
        # https://manpages.ubuntu.com/manpages/jammy/man8/apt-get.8.html
        # Remove packages installed temporarily. Removes everything related to
        # packages, including the configuration files, and packages
        # automatically installed because a package required them but, with the
        # other packages removed, are no longer needed.
        # apt-get purge -y --auto-remove curl && \
        # Delete local repository of retrieved package files in /var/cache/apt/archives
        # This is handled automatically by /etc/apt/apt.conf.d/docker-clean
        # Use this if not running --mount=type=cache.
        # apt-get clean && \
        # Delete info on installed packages. This saves some space, but it can
        # be useful to have them as a record of what was installed, e.g. for auditing.
        # rm -rf /var/lib/dpkg && \
        # Delete debconf data files to save some space
        # rm -rf /var/cache/debconf && \
        # Delete index of available files from apt-get update
        # Use this if not running --mount=type=cache.
        # rm -rf /var/lib/apt/lists/*
        # Clear logs of installed packages
        truncate -s 0 /var/log/apt/* && \
        truncate -s 0 /var/log/dpkg.log

    RUN chsh --shell /bin/bash "$APP_USER"

    ENV O=/opt/buildroot_output

    ENV BUILDROOT_GIT_REPO=$BUILDROOT_GIT_REPO \
        BUILDROOT_TAG=$BUILDROOT_TAG \
        BUILDROOT_BOARD=$BUILDROOT_BOARD \
        BUILDROOT_DEFCONFIG=$BUILDROOT_DEFCONFIG

    RUN set -exu && \
        mkdir -p /opt/buildroot && \
        chown $APP_USER /opt/buildroot && \
        mkdir -p /opt/buildroot_output && \
        chown $APP_USER /opt/buildroot_output && \
        mkdir -p /buildroot && \
        chown $APP_USER /buildroot

    USER $APP_USER

    WORKDIR /opt/buildroot

    # [ -d /opt/buildroot/.git ] || git clone $BUILDROOT_GIT_REPO /opt/buildroot
    # git config pull.rebase true \
    # git checkout $BUILDROOT_TAG && \
    # git pull origin $BUILDROOT_TAG
    # make BR2_EXTERNAL="/buildroot" $BUILDROOT_DEFCONFIG
    # make
    # cp /opt/buildroot/output/images/sdcard.img /buildroot
