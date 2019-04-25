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

branch=`git symbolic-ref --short HEAD`
commit=`git log --format=%h -1`

[ ! -f dl/devsus-kernel.tar.gz ] && wget -O dl/devsus-kernel.tar.gz https://github.com/dimkr/devsus/releases/download/$branch-$commit/devsus-kernel.tar.gz
[ ! -f dl/devsus-firmware.tar.gz ] && wget -O dl/devsus-firmware.tar.gz https://github.com/dimkr/devsus/releases/download/$branch-$commit/devsus-firmware.tar.gz
[ ! -f dl/devsus-rootfs.tar.gz ] && wget -O dl/devsus-rootfs.tar.gz https://github.com/dimkr/devsus/releases/download/$branch-$commit/devsus-rootfs.tar.gz
[ ! -f dl/devsus-templates.tar.gz ] && wget -O dl/devsus-templates.tar.gz https://github.com/dimkr/devsus/releases/download/$branch-$commit/devsus-templates.tar.gz

tar -xzf dl/devsus-templates.tar.gz

trap cleanup INT TERM EXIT

# mount the / partition of both images
off=$(((8192 + 65536) * 512))
mount -o loop,noatime,offset=$off devuan-ascii-c201-libre-2GB.img $outmnt
mount -o loop,noatime,offset=$off devuan-ascii-c201-libre-16GB.img $inmnt

# unpack Devuan
for i in rootfs kernel firmware
do
	tar -C $outmnt -xf dl/devsus-$i.tar.gz --strip-components=1
done
cp -a $outmnt/* $inmnt/

# put the kernel in the kernel partition
dd if=$outmnt/boot/vmlinux.kpart of=devuan-ascii-c201-libre-2GB.img conv=notrunc seek=8192
dd if=$outmnt/boot/vmlinux.kpart of=devuan-ascii-c201-libre-16GB.img conv=notrunc seek=8192

umount -l $inmnt
rmdir $inmnt

# put the 16GB image inside the 2GB one
cp -f --sparse=always devuan-ascii-c201-libre-16GB.img $outmnt/
