#!/bin/sh -xe

#  this file is part of Devsus.
#
#  Copyright 2017 Dima Krasner
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

trap cleanup INT TERM EXIT

# build the Chrome OS kernel, with ath9k_htc and without many useless drivers
[ ! -d chromeos-3.14 ] && git clone --depth 1 -b chromeos-3.14 https://chromium.googlesource.com/chromiumos/third_party/kernel chromeos-3.14
[ ! -f deblob-3.14 ] && wget http://linux-libre.fsfla.org/pub/linux-libre/releases/LATEST-3.14.N/deblob-3.14
[ ! -f deblob-check ] && wget http://linux-libre.fsfla.org/pub/linux-libre/releases/LATEST-3.14.N/deblob-check
cd chromeos-3.14
# deblob as much as possible - the diff against vanilla 3.14.x is big but
# blob-free ath9k_htc should be only driver that requests firmware
AWK=gawk sh ../deblob-3.14 --force
export WIFIVERSION=-3.8
./chromeos/scripts/prepareconfig chromiumos-rockchip
cp ../config .config
make -j `grep ^processor /proc/cpuinfo  | wc -l` CROSS_COMPILE=arm-none-eabi- ARCH=arm zImage modules dtbs
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
[ ! -d open-ath9k-htc-firmware ] && git clone --depth 1 https://github.com/qca/open-ath9k-htc-firmware.git
cd open-ath9k-htc-firmware
make toolchain
make -C target_firmware
cd ..

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

# create a 2GB image with the Chrome OS partition layout
create_image devuan-jessie-c201-libre-2GB.img $outdev 50M 40 $outmnt

# install Devuan on it
qemu-debootstrap --arch=armhf --foreign jessie --variant minbase $outmnt http://packages.devuan.org/merged
chroot $outmnt passwd -d root
echo -n devsus > $outmnt/etc/hostname
install -D -m 644 80disable-recommends $outmnt/etc/apt/apt.conf.d/80disable-recommends
cp -f /etc/resolv.conf $outmnt/etc/
chroot $outmnt apt update
chroot $outmnt apt install -y udev kmod net-tools inetutils-ping traceroute iproute2 isc-dhcp-client wpasupplicant iw alsa-utils cgpt vim-tiny less psmisc netcat-openbsd ca-certificates bzip2 xz-utils unscd
chroot $outmnt apt-get autoremove
chroot $outmnt apt-get clean
sed -i s/^[3-6]/\#\&/g $outmnt/etc/inittab
sed -i s/'enable-cache            hosts   no'/'enable-cache            hosts   yes'/ -i $outmnt/etc/nscd.conf
rm -f $outmnt/etc/resolv.conf

# put the kernel in the kernel partition, modules in /lib/modules and AR9271
# firmware in /lib/firmware
dd if=chromeos-3.14/vmlinux.kpart of=${outdev}p1 conv=notrunc
make -C chromeos-3.14 ARCH=arm INSTALL_MOD_PATH=$outmnt modules_install
rm -f $outmnt/lib/modules/3.14.0/{build,source}
install -D -m 644 open-ath9k-htc-firmware/target_firmware/htc_9271.fw $outmnt/lib/firmware/htc_9271.fw

# create a 16GB image
create_image devuan-jessie-c201-libre-16GB.img $indev 512 30785536 $inmnt

# copy the kernel and / of the 2GB image to the 16GB one
dd if=${outdev}p1 of=${indev}p1 conv=notrunc
cp -a $outmnt/* $inmnt/

umount -l $inmnt
rmdir $inmnt
losetup -d $indev

# move the 16GB image inside the 2GB one
cp -f devuan-jessie-c201-libre-16GB.img $outmnt/
