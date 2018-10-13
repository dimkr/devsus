```
     _
  __| | _____   _____ _   _ ___
 / _` |/ _ \ \ / / __| | | / __|
| (_| |  __/\ V /\__ \ |_| \__ \
 \__,_|\___| \_/ |___/\__,_|___/
```

[![Build Status](https://travis-ci.org/dimkr/devsus.svg?branch=master)](https://travis-ci.org/dimkr/devsus)

Overview
========

Devsus is a script that builds bootable, libre [Devuan](http://www.devuan.org/) images for the Asus C201 Chromebook, one of the few laptops able to boot and run without any non-free software, all the way down to the firmware level. The C201 is supported by [Libreboot](http://www.libreboot.org/).

The images produced by Devsus contain the latest [Linux-libre](http://linux-libre.fsfla.org/) 4.9.x kernel, tuned for small size, good performance and short boot times. This kernel branch has been chosen for its [longterm](https://www.kernel.org/category/releases.html) status, which means that freedom-respecting C201 laptops are usable at least until this kernel branch is phased out.

Some features of the Rockchip RK3288 SoC, including built-in WiFi support, require use of non-free software. Therefore, they are unsupported by Devsus. To compensate for that, the Devsus kernel includes support for freedom-friendly devices:

* Firmware for Atheros AR9271 based WiFi dongles
* Drivers for Qualcomm CSR8510 based Bluetooth dongles

Also, the images contain:
* Crucial command-line tools, like those required to connect to a WiFi network
* A [Ratpoison](https://www.nongnu.org/ratpoison/)-based, keyboard-controlled, graphical environment
* [Firefox](https://www.mozilla.org/en-US/firefox/) ESR, pre-configured for enhanced privacy and responsiveness on the C201

Releases
========

Devsus' root file system is built by a CI/CD flow on [Travis CI](https://travis-ci.org/dimkr/devsus), that operates on the Devsus master branch. This file system contains an up-to-date kernel, kernel modules, firmware and Devuan.

The root file system is put in a tarball that is uploaded to [GitHub](https://github.com/dimkr/devsus/releases).

In order to run Devsus, one has to unpack this tarball onto an existing bootable media, or produce bootable images.

Usage
=====

	# apt install --no-install-recommends --no-install-suggests parted cgpt
	# ./devsus.sh

This downloads the root file system tarball and creates two Devuan disk images:

1. devuan-ascii-c201-libre-16GB.img, a 16 GB image suitable for persistent installation; its size should be exactly the size of the internal SSD
2. devuan-ascii-c201-libre-2GB.img, a 2 GB image suitable for booting the laptop off USB

To produce a bootable media, write the 2 GB image to a flash drive (of at least 2 GB):

	# dd if=$SOMEWHERE/devuan-ascii-c201-libre-2GB.img of=/dev/$DEVICE bs=50M

During the first boot, packages will be installed and configured. Once packages are configured, the login prompt will appear; the root password is blank.

The 2 GB image (yes, the smaller one) contains the larger, 16 GB one under /. This way, it is possible to boot the laptop through USB, then install Devuan persistently without having to download or store the large image separately.

Persistent installation is performed using dd, too:

	# dd if=/devuan-ascii-c201-libre-16GB.img of=/dev/mmcblk0

Graphical Desktop
=================

First, create a regular user:

	# useradd -m -s /bin/bash user_name_goes_here
	# passwd user_name_goes_here

Then, log in as the new user.

To start the graphical desktop:

	$ startx

The browser and the terminal are started automatically.

The window manager is controlled using the keyboard:

* Search + c spawns a new terminal window
* Search + n switches to the next window
* Search + p switches to the previous window
* Search + k closes a window
* Search + ! run a shell command

The special actions of function keys are triggered by pressing them together with the control key.

For a list of all key bindings:

	$ man ratpoison
	$ cat ~/.xbindkeysrc

Credits and Legal Information
=============================

Devsus' previous kernel building procedure was based on the linux-veyron package
of [Arch Linux ARM](http://www.archlinuxarm.org/).

Devsus' workaround for ath9k_htc instability issues has been adopted from [PrawnOS](https://github.com/SolidHal/PrawnOS) and found by SolidHal.

Devsus is free and unencumbered software released under the terms of the GNU General Public License, version 2; see COPYING for the license text. For a list of its authors and contributors, see AUTHORS.

The ASCII art logo at the top was made using [FIGlet](http://www.figlet.org/).
