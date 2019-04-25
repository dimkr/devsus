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

[ ! -d open-ath9k-htc-firmware ] && git clone --depth 1 https://github.com/qca/open-ath9k-htc-firmware.git

# build AR9271 firmware
cd open-ath9k-htc-firmware
if [ -d ../cache/xtensa-toolchain ]
then
	mkdir toolchain
	mv ../cache/xtensa-toolchain toolchain/inst
else
	make toolchain
fi
CROSS_COMPILE=`pwd`/../ci/xtensa-elf- make -C target_firmware
mv toolchain/inst ../cache/xtensa-toolchain
cd ..

# put AR9271 firmware in /lib/firmware
install -D -m 644 open-ath9k-htc-firmware/target_firmware/htc_9271.fw devsus-firmware/lib/firmware/htc_9271.fw
tar -c devsus-firmware | gzip -1 > devsus-firmware.tar.gz
