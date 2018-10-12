#!/bin/sh -xe

#  this file is part of Devsus.
#
#  Copyright 2017, 2018 Dima Krasner
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

outmnt=$(mktemp -d -p `pwd`)
inmnt=$(mktemp -d -p `pwd`)

outdev=/dev/loop6
indev=/dev/loop7

cleanup() {
	set +e

	umount -l $inmnt > /dev/null 2>&1
	rmdir $inmnt > /dev/null 2>&1
	losetup -d $indev > /dev/null 2>&1

	umount -l $outmnt > /dev/null 2>&1
	rmdir $outmnt > /dev/null 2>&1
	losetup -d $outdev > /dev/null 2>&1
}

[ "$CI" != true ] && trap cleanup INT TERM EXIT

minor=`wget -q -O- http://linux-libre.fsfla.org/pub/linux-libre/releases/LATEST-$KVER.N/ | grep -F patch-$KVER-gnu | head -n 1 | cut -f 9 -d . | cut -f 1 -d -`
[ ! -f linux-libre-$KVER-gnu.tar.xz ] && wget http://linux-libre.fsfla.org/pub/linux-libre/releases/LATEST-4.9.0/linux-libre-$KVER-gnu.tar.xz
[ ! -f patch-$KVER-gnu-$KVER.$minor-gnu ] && wget -O- https://www.linux-libre.fsfla.org/pub/linux-libre/releases/LATEST-$KVER.N/patch-$KVER-gnu-$KVER.$minor-gnu.xz | xz -d > patch-$KVER-gnu-$KVER.$minor-gnu
[ ! -f ath9k_htc_do_not_use_bulk_on_ep3_and_ep4.patch ] && wget -O ath9k_htc_do_not_use_bulk_on_ep3_and_ep4.patch https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/patch/?id=2b721118b7821107757eb1d37af4b60e877b27e7
[ ! -d open-ath9k-htc-firmware ] && git clone --depth 1 https://github.com/qca/open-ath9k-htc-firmware.git
[ ! -f hosts ] && wget -O- https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews/hosts | grep ^0\.0\.0\.0 | awk '{print $1" "$2}' | grep -F -v "0.0.0.0 0.0.0.0" > hosts

# build Linux-libre
[ ! -d linux-$KVER ] && tar -xJf linux-libre-$KVER-gnu.tar.xz
cd linux-$KVER
patch -p 1 < ../patch-$KVER-gnu-$KVER.$minor-gnu
make clean
make mrproper
# work around instability of ath9k_htc, see https://github.com/SolidHal/PrawnOS/issues/38
patch -R -p 1 < ../ath9k_htc_do_not_use_bulk_on_ep3_and_ep4.patch
# reset the minor version number, so out-of-tree drivers continue to work after
# a kernel upgrade
sed s/'SUBLEVEL = .*'/'SUBLEVEL = 0'/ -i Makefile
cp -f ../config .config

kmake="make -j `grep ^processor /proc/cpuinfo  | wc -l` CROSS_COMPILE=arm-none-eabi- ARCH=arm"

$kmake olddefconfig
$kmake modules_prepare
$kmake SUBDIRS=drivers/usb/dwc2 modules
$kmake SUBDIRS=drivers/net/wireless/ath/ath9k modules
$kmake SUBDIRS=drivers/bluetooth modules
$kmake dtbs

$kmake zImage modules

[ ! -h kernel.its ] && ln -s ../kernel.its .
mkimage -D "-I dts -O dtb -p 2048" -f kernel.its vmlinux.uimg
dd if=/dev/zero of=bootloader.bin bs=512 count=1
vbutil_kernel --pack vmlinux.kpart \
              --version 1 \
              --vmlinuz vmlinux.uimg \
              --arch arm \
              --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
              --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
              --config ../cmdline \
              --bootloader bootloader.bin
cd ..

# build AR9271 firmware
if [ "$CI" != true ]
then
	cd open-ath9k-htc-firmware
	make toolchain
	make -C target_firmware
	cd ..
fi

create_image() {
	# it's a sparse file - that's how we fit a 16GB image inside a 2GB one
	dd if=/dev/zero of=$1 bs=$3 count=$4 conv=sparse
	parted --script $1 mklabel gpt
	cgpt create $1
	cgpt add -i 1 -t kernel -b 8192 -s 65536 -l Kernel -S 1 -T 5 -P 10 $1
	start=$((8192 + 65536))
	end=`cgpt show $1 | grep 'Sec GPT table' | awk '{print $1}'`
	size=$(($end - $start))
	cgpt add -i 2 -t data -b $start -s $size -l Root $1
	# $size is in 512 byte blocks while ext4 uses a block size of 1024 bytes
	losetup -P $2 $1
	mkfs.ext4 -F -b 1024 -m 0 -O ^has_journal ${2}p2 $(($size / 2))

	# mount the / partition
	mount -o noatime ${2}p2 $5
}

install_devuan() {
	debootstrap --arch=armhf --foreign ascii --variant minbase $1 http://packages.devuan.org/merged eudev kmod net-tools inetutils-ping traceroute iproute2 isc-dhcp-client wpasupplicant iw alsa-utils cgpt elvis-tiny less psmisc netcat-traditional ca-certificates bzip2 xz-utils unscd dbus dbus-x11 bluez pulseaudio pulseaudio-module-bluetooth elogind libpam-elogind ntp xserver-xorg-core xserver-xorg-input-libinput xserver-xorg-video-fbdev libgl1-mesa-dri xserver-xorg-input-synaptics xinit x11-xserver-utils ratpoison xbindkeys xvkbd rxvt-unicode htop firefox-esr mupdf locales man-db dmz-cursor-theme apt-transport-https

	install -D -m 644 devsus/sources.list $1/opt/devsus/sources.list
	for i in 80disable-recommends hosts 99-brightness.rules 98-mac.rules fstab .xbindkeysrc htoprc .Xresources .ratpoisonrc 99-hinting.conf index.theme devsus-settings.js devsus.cfg
	do
	done
		install -m 644 devsus/$i $1/opt/devsus/$i
	done
	install -m 744 devsus/.xinitrc $1/opt/devsus/.xinitrc

	# put kernel modules in /lib/modules and AR9271 firmware in /lib/firmware
	$kmake -C linux-$KVER INSTALL_MOD_PATH=$1 modules_install
	rm -f $1/lib/modules/$KVER.0-gnu/{build,source}
	[ "$CI" != true ] && install -D -m 644 open-ath9k-htc-firmware/target_firmware/htc_9271.fw $1/lib/firmware/htc_9271.fw
}

if [ "$CI" = true ]
then
	install_devuan rootfs
	install -D -m 644 linux-$KVER/vmlinux.kpart rootfs/boot/vmlinux.kpart
	tar -c rootfs | gzip -9 > devsus.tar.gz
	exit 0
fi

# create a 2GB image with the Chrome OS partition layout
create_image devuan-ascii-c201-libre-2GB.img $outdev 50M 40 $outmnt

# install Devuan on it
install_devuan $outmnt

# put the kernel in the kernel partition
dd if=linux-$KVER/vmlinux.kpart of=${outdev}p1 conv=notrunc

# create a 16GB image
create_image devuan-ascii-c201-libre-16GB.img $indev 512 30785536 $inmnt

# copy the kernel and / of the 2GB image to the 16GB one
dd if=${outdev}p1 of=${indev}p1 conv=notrunc
cp -a $outmnt/* $inmnt/

umount -l $inmnt
rmdir $inmnt
losetup -d $indev

# move the 16GB image inside the 2GB one
cp -f devuan-ascii-c201-libre-16GB.img $outmnt/
