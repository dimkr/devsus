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

here=`pwd`
outmnt=$(mktemp -d -p $here)
inmnt=$(mktemp -d -p $here)

cleanup() {
	set +e

	umount -l $inmnt > /dev/null 2>&1
	rmdir $inmnt > /dev/null 2>&1

	umount -l $outmnt > /dev/null 2>&1
	rmdir $outmnt > /dev/null 2>&1
}

install_devuan() {
	debootstrap --arch=armhf --foreign --variant=minbase --include=eudev,kmod,net-tools,inetutils-ping,traceroute,iproute2,isc-dhcp-client,wpasupplicant,iw,alsa-utils,cgpt,elvis-tiny,less,psmisc,netcat-traditional,ca-certificates,bzip2,xz-utils,unscd,dbus,dbus-x11,bluez,pulseaudio,pulseaudio-module-bluetooth,elogind,libpam-elogind,ntp,xserver-xorg-core,xserver-xorg-input-libinput,xserver-xorg-video-fbdev,libgl1-mesa-dri,xserver-xorg-input-synaptics,xinit,x11-xserver-utils,ratpoison,xbindkeys,xvkbd,rxvt-unicode,htop,firefox-esr,mupdf,locales,man-db,dmz-cursor-theme,apt-transport-https ascii $1 http://packages.devuan.org/merged

	install -D -m 644 devsus/sources.list $1/opt/devsus/sources.list
	for i in 80disable-recommends 99-brightness.rules 98-mac.rules fstab .xbindkeysrc htoprc .Xresources .ratpoisonrc 99-hinting.conf index.theme devsus-settings.js devsus.cfg
	do
		install -m 644 devsus/$i $1/opt/devsus/$i
	done
	install -m 644 dl/hosts $1/opt/devsus/hosts
	install -m 744 devsus/.xinitrc $1/opt/devsus/.xinitrc
	install -m 755 devsus/init $1/opt/devsus/init

	# put kernel modules in /lib/modules and AR9271 firmware in /lib/firmware
	$kmake -C linux-$KVER INSTALL_MOD_PATH=$1 modules_install
	rm -f $1/lib/modules/$KVER.0-gnu/{build,source}
	install -D -m 644 open-ath9k-htc-firmware/target_firmware/htc_9271.fw $1/lib/firmware/htc_9271.fw

	return 0
}

create_image() {
	# it's a sparse file - that's how we fit a 16GB image inside a 2GB one
	dd if=/dev/zero of=$1 bs=$2 count=$3 conv=sparse
	parted --script $1 mklabel gpt
	cgpt create $1
	cgpt add -i 1 -t kernel -b 8192 -s 65536 -l Kernel -S 1 -T 5 -P 10 $1
	start=$((8192 + 65536))
	end=`cgpt show $1 | grep 'Sec GPT table' | awk '{print $1}'`
	size=$(($end - $start))
	cgpt add -i 2 -t data -b $start -s $size -l Root $1
	# $size is in 512 byte blocks while ext4 uses a block size of 1024 bytes
	mkfs.ext4 -F -b 1024 -m 0 -O ^has_journal -E offset=$(($start * 512)) $1 $(($size / 2))
}

if [ "$CI" = true ]
then
	minor=`wget -q -O- http://linux-libre.fsfla.org/pub/linux-libre/releases/LATEST-$KVER.N/ | grep -F patch-$KVER-gnu | head -n 1 | cut -f 9 -d . | cut -f 1 -d -`
	[ ! -f dl/linux-libre-$KVER-gnu.tar.xz ] && wget -O dl/linux-libre-$KVER-gnu.tar.xz http://linux-libre.fsfla.org/pub/linux-libre/releases/LATEST-$KVER.0/linux-libre-$KVER-gnu.tar.xz
	[ ! -f dl/patch-$KVER-gnu-$KVER.$minor-gnu ] && wget -O- https://www.linux-libre.fsfla.org/pub/linux-libre/releases/LATEST-$KVER.N/patch-$KVER-gnu-$KVER.$minor-gnu.xz | xz -d > dl/patch-$KVER-gnu-$KVER.$minor-gnu
	[ ! -f dl/ath9k_htc_do_not_use_bulk_on_ep3_and_ep4.patch ] && wget -O dl/ath9k_htc_do_not_use_bulk_on_ep3_and_ep4.patch https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/patch/?id=2b721118b7821107757eb1d37af4b60e877b27e7
	[ ! -f dl/hosts ] && wget -O- https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews/hosts | grep ^0\.0\.0\.0 | awk '{print $1" "$2}' | grep -F -v "0.0.0.0 0.0.0.0" > dl/hosts
	[ ! -d open-ath9k-htc-firmware ] && git clone --depth 1 https://github.com/qca/open-ath9k-htc-firmware.git

	# build Linux-libre
	[ ! -d linux-$KVER ] && tar -xJf dl/linux-libre-$KVER-gnu.tar.xz
	cd linux-$KVER
	patch -p 1 < ../dl/patch-$KVER-gnu-$KVER.$minor-gnu
	make clean
	make mrproper
	# work around instability of ath9k_htc, see https://github.com/SolidHal/PrawnOS/issues/38
	patch -R -p 1 < ../dl/ath9k_htc_do_not_use_bulk_on_ep3_and_ep4.patch
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
	cd open-ath9k-htc-firmware
	if [ -d ../dl/xtensa-toolchain ]
	then
		mkdir toolchain
		mv ../dl/xtensa-toolchain toolchain/inst
	else
		make toolchain
	fi
	make -C target_firmware
	mv toolchain/inst ../dl/xtensa-toolchain
	cd ..

	install_devuan $here/devsus-rootfs
	install -D -m 644 linux-$KVER/vmlinux.kpart devsus-rootfs/boot/vmlinux.kpart
	tar -c devsus-rootfs | gzip -1 > devsus-rootfs.tar.gz

	# create 2GB and 16GB images with the Chrome OS partition layout
	create_image devuan-ascii-c201-libre-2GB.img 50M 40
	create_image devuan-ascii-c201-libre-16GB.img 512 30785536
	GZIP=-1 tar -cSzf devsus-templates.tar.gz devuan-ascii-c201-libre-2GB.img devuan-ascii-c201-libre-16GB.img
else
	branch=`git symbolic-ref --short HEAD`
	commit=`git log --format=%h -1`

	[ ! -f dl/devsus-rootfs.tar.gz ] && wget -O dl/devsus-rootfs.tar.gz https://github.com/dimkr/devsus/releases/download/$branch-$commit/devsus-rootfs.tar.gz
	[ ! -f dl/devsus-templates.tar.gz ] && wget -O dl/devsus-templates.tar.gz https://github.com/dimkr/devsus/releases/download/$branch-$commit/devsus-templates.tar.gz

	tar -xzf dl/devsus-templates.tar.gz

	trap cleanup INT TERM EXIT

	# mount the / partition of both images
	off=$(((8192 + 65536) * 512))
	mount -o loop,noatime,offset=$off devuan-ascii-c201-libre-2GB.img $outmnt
	mount -o loop,noatime,offset=$off devuan-ascii-c201-libre-16GB.img $inmnt

	# unpack Devuan
	tar -C $outmnt -xf dl/devsus-rootfs.tar.gz --strip-components=1
	cp -a $outmnt/* $inmnt/

	# put the kernel in the kernel partition
	dd if=$outmnt/boot/vmlinux.kpart of=devuan-ascii-c201-libre-2GB.img conv=notrunc seek=8192
	dd if=$outmnt/boot/vmlinux.kpart of=devuan-ascii-c201-libre-16GB.img conv=notrunc seek=8192

	umount -l $inmnt
	rmdir $inmnt

	# put the 16GB image inside the 2GB one
	cp -f --sparse=always devuan-ascii-c201-libre-16GB.img $outmnt/
fi
