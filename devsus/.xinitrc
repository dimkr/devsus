#!/bin/sh

xrdb -merge ~/.Xresources
xsetroot -solid \#333333
xbindkeys
synclient HorizTwoFingerScroll=1
synclient TapButton2=2
synclient TapButton1=1
urxvtd -q -f -o
firefox-esr &
urxvtc &
exec ratpoison
