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

[ ! -f hosts ] && wget -O- https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews/hosts | grep ^0\.0\.0\.0 | awk '{print $1" "$2}' | grep -F -v "0.0.0.0 0.0.0.0" > hosts

debootstrap --arch=armhf --foreign --variant=minbase --include=eudev,kmod,net-tools,inetutils-ping,traceroute,iproute2,isc-dhcp-client,wpasupplicant,iw,alsa-utils,cgpt,elvis-tiny,less,psmisc,netcat-traditional,ca-certificates,bzip2,xz-utils,unscd,dbus,dbus-x11,bluez,pulseaudio,pulseaudio-module-bluetooth,elogind,libpam-elogind,ntp,xserver-xorg-core,xserver-xorg-input-libinput,xserver-xorg-video-fbdev,libgl1-mesa-dri,xserver-xorg-input-synaptics,xinit,x11-xserver-utils,ratpoison,xbindkeys,xvkbd,rxvt-unicode,htop,firefox-esr,mupdf,locales,man-db,dmz-cursor-theme,apt-transport-https ascii devsus-rootfs http://packages.devuan.org/merged

install -D -m 644 devsus/sources.list devsus-rootfs/opt/devsus/sources.list
for i in 80disable-recommends 99-brightness.rules 98-mac.rules fstab .xbindkeysrc htoprc .Xresources .ratpoisonrc 99-hinting.conf index.theme devsus-settings.js devsus.cfg
do
	install -m 644 devsus/$i devsus-rootfs/opt/devsus/$i
done
install -m 644 hosts devsus-rootfs/opt/devsus/hosts
install -m 744 devsus/.xinitrc devsus-rootfs/opt/devsus/.xinitrc
install -m 755 devsus/init devsus-rootfs/opt/devsus/init

tar -c devsus-rootfs | gzip -1 > devsus-rootfs.tar.gz
