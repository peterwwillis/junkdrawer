#!/usr/bin/env sh

sudo chvt 2
sleep 3
xrandr --display :0.0 --auto
xrandr --display :1.0 --auto
xrandr --display :2.0 --auto
