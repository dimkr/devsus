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

# create 2GB and 16GB images with the Chrome OS partition layout
create_image devuan-ascii-c201-libre-2GB.img 50M 40
create_image devuan-ascii-c201-libre-16GB.img 512 30785536
GZIP=-1 tar -cSzf devsus-templates.tar.gz devuan-ascii-c201-libre-2GB.img devuan-ascii-c201-libre-16GB.img
