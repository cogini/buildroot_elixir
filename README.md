# buildroot_elixir

This is an example of using the [Buildroot](https://buildroot.org/) embedded
Linux build system to run an Elixir app.

It has support for building in Docker and GitHub Actions CI.

## Running in Docker

Create an `.env` file:
```shell
IMAGE_NAME="foo-app"
IMAGE_OWNER="cogini"
```

Build dev image:

```command
docker compose build
```

Run dev image:

```command
docker compose run buildroot-dev
```

Inside the container

```command
[ -d /opt/buildroot/.git ] || git clone $BUILDROOT_GIT_REPO /opt/buildroot
git checkout $BUILDROOT_TAG && \
git pull origin $BUILDROOT_TAG
make BR2_EXTERNAL="/buildroot" $BUILDROOT_DEFCONFIG
make
cp /opt/buildroot/output/images/sdcard.img /tmp/output
```

## Useful buildroot commands

Configure buildroot:

    make menuconfig

Save buildroot config to `buildroot_ec2/configs/ec2_defconfig`:

    make savedefconfig

Use a different kernel config:

    cp ~/nixos-4.14.32.config output/build/linux-4.16.13/.config

Configure Linux kernel

    make linux-menuconfig

Save to `.config`, then save the kernel config back to `buildroot_ec2/board/ec2/linux.config`:

    make linux-savedefconfig

See the available buildroot configs

```shell
make list-defconfigs
```

