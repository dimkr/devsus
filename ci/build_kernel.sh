#!/bin/sh -xe

#  this file is part of Devsus.
#
#  Copyright 2017, 2018, 2019 Dima Krasner
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
#  MA 02110-1301, USA.

KVER=4.9

here=`pwd`

minor=`wget -q -O- http://linux-libre.fsfla.org/pub/linux-libre/releases/LATEST-$KVER.N/ | grep -F patch-$KVER-gnu | head -n 1 | cut -f 9 -d . | cut -f 1 -d -`
[ ! -f kernel-cache/linux-libre-$KVER-gnu.tar.xz ] && wget -O kernel-cache/linux-libre-$KVER-gnu.tar.xz http://linux-libre.fsfla.org/pub/linux-libre/releases/LATEST-$KVER.0/linux-libre-$KVER-gnu.tar.xz
[ ! -f kernel-cache/patch-$KVER-gnu-$KVER.$minor-gnu ] && wget -O- https://www.linux-libre.fsfla.org/pub/linux-libre/releases/LATEST-$KVER.N/patch-$KVER-gnu-$KVER.$minor-gnu.xz | xz -d > kernel-cache/patch-$KVER-gnu-$KVER.$minor-gnu
[ ! -f kernel-cache/ath9k_htc_do_not_use_bulk_on_ep3_and_ep4.patch ] && wget -O kernel-cache/ath9k_htc_do_not_use_bulk_on_ep3_and_ep4.patch https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/patch/?id=2b721118b7821107757eb1d37af4b60e877b27e7

# build Linux-libre
[ ! -d linux-$KVER ] && tar -xJf kernel-cache/linux-libre-$KVER-gnu.tar.xz
cd linux-$KVER
patch -p 1 < ../kernel-cache/patch-$KVER-gnu-$KVER.$minor-gnu
make clean
make mrproper
# work around instability of ath9k_htc, see https://github.com/SolidHal/PrawnOS/issues/38
patch -R -p 1 < ../kernel-cache/ath9k_htc_do_not_use_bulk_on_ep3_and_ep4.patch
# reset the minor version number, so out-of-tree drivers continue to work after
# a kernel upgrade
sed s/'SUBLEVEL = .*'/'SUBLEVEL = 0'/ -i Makefile
cp -f ../kernel/config .config

export PATH=$here/ci:$PATH
kmake="make -j `nproc` CROSS_COMPILE=arm-none-eabi- ARCH=arm"

$kmake olddefconfig
$kmake modules_prepare
$kmake SUBDIRS=drivers/usb/dwc2 modules
$kmake SUBDIRS=drivers/net/wireless/ath/ath9k modules
$kmake SUBDIRS=drivers/bluetooth modules
$kmake dtbs

$kmake zImage modules

[ ! -h kernel.its ] && ln -s ../kernel/kernel.its .
mkimage -D "-I dts -O dtb -p 2048" -f kernel.its vmlinux.uimg
dd if=/dev/zero of=bootloader.bin bs=512 count=1
mkdir -p ../devsus-kernel/boot
vbutil_kernel --pack ../devsus-kernel/boot/vmlinux.kpart \
              --version 1 \
              --vmlinuz vmlinux.uimg \
              --arch arm \
              --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
              --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
              --config ../kernel/cmdline \
              --bootloader bootloader.bin
cd ..

# put kernel modules in /lib/modules
$kmake -C linux-$KVER INSTALL_MOD_PATH=$here/devsus-kernel modules_install
rm -f devsus-kernel/lib/modules/$KVER.0-gnu/{build,source}
tar -c devsus-kernel | gzip -1 > devsus-kernel.tar.gz
