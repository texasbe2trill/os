#!/bin/bash

set -e

# check for root permissions
if [[ "$(id -u)" != 0 ]]; then
  echo "E: Requires root permissions" > /dev/stderr
  exit 1
fi

# get config
if [ -n "$1" ]; then
  CONFIG_FILE="$1"
else
  CONFIG_FILE="etc/terraform.conf"
fi

# Use a container-local build directory to avoid noexec issues
CONTAINER_BUILD_DIR="/tmp/build"
HOST_WORKING_DIR="$PWD"
source "$HOST_WORKING_DIR"/"$CONFIG_FILE"

echo -e "
#----------------------#
# INSTALL DEPENDENCIES #
#----------------------#
"

apt-get update
apt-get install -y live-build patch gnupg2 binutils zstd

gpg --homedir /tmp --no-default-keyring --keyring /etc/apt/trusted.gpg --recv-keys --keyserver keyserver.ubuntu.com F6ECB3762474EDA9D21B7022871920D1991BC93C

ln -sfn /usr/share/debootstrap/scripts/gutsy /usr/share/debootstrap/scripts/noble

build () {
  BUILD_ARCH="$1"

  mkdir -p "$CONTAINER_BUILD_DIR/tmp/$BUILD_ARCH"
  cd "$CONTAINER_BUILD_DIR/tmp/$BUILD_ARCH" || exit

  # remove old configs and copy over new
  rm -rf config auto
  cp -r "$HOST_WORKING_DIR"/etc/* .
  cp -f "$HOST_WORKING_DIR"/"$CONFIG_FILE" terraform.conf

  if [ "$INCLUDE_APPCENTER" = "yes" ]; then
    cp "config/appcenter/appcenter.list.binary" "config/archives/appcenter.list.binary"
    cp "config/appcenter/appcenter.key.binary" "config/archives/appcenter.key.binary"
  fi

  echo -e "
#------------------#
# LIVE-BUILD CLEAN #
#------------------#
"
  lb clean

  echo -e "
#-------------------#
# LIVE-BUILD CONFIG #
#-------------------#
"
  lb config

  echo -e "
#------------------#
# LIVE-BUILD BUILD #
#------------------#
"
  lb build

  echo -e "
#---------------------------#
# MOVE OUTPUT TO BUILDS DIR #
#---------------------------#
"

  YYYYMMDD="$(date +%Y%m%d)"
  OUTPUT_DIR="$CONTAINER_BUILD_DIR/builds/$BUILD_ARCH"
  mkdir -p "$OUTPUT_DIR"
  FNAME="elementaryos-$VERSION-$CHANNEL.$YYYYMMDD$OUTPUT_SUFFIX"
  mv "$CONTAINER_BUILD_DIR/tmp/$BUILD_ARCH/live-image-$BUILD_ARCH.hybrid.iso" "$OUTPUT_DIR/${FNAME}.iso"

  cd $OUTPUT_DIR
  md5sum "${FNAME}.iso" | tee "${FNAME}.md5.txt"
  sha256sum "${FNAME}.iso" | tee "${FNAME}.sha256.txt"
  cd $CONTAINER_BUILD_DIR

  # Copy output back to host working directory
  mkdir -p "$HOST_WORKING_DIR/builds/$BUILD_ARCH"
  cp "$OUTPUT_DIR/"* "$HOST_WORKING_DIR/builds/$BUILD_ARCH/"
}

# remove old builds before creating new ones (on host)
rm -rf "$HOST_WORKING_DIR"/builds

if [[ "$ARCH" == "all" ]]; then
    build amd64
    build i386
else
    build "$ARCH"
fi