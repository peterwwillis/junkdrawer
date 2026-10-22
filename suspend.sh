#!/usr/bin/env sh
# suspend.sh - Suspend the system and play music on a loop when it resumes, in case it wakes up in your bag
sudo pm-suspend
pmret=$?
if [ $pmret -eq 0 ] ; then
    msg="System has suspended and resumed successfully."
elif [ $pmret -lt 128 ] ; then
    msg="System failed before trying to put the system in the requested power saving state."
elif [ $pmret -eq 128 ] ; then
    msg="System tried to put the machine in the requested power state but failed."
elif [ $pmret -gt 128 ] ; then
    msg="System encountered an error and also failed to enter the requested power saving state."
fi
mplayer -really-quiet -loop 0 /usr/share/sounds/oxygen/stereo/desktop-login.ogg >/dev/null 2>&1 &
mppid=$!
xmessage -center -buttons Ok "$msg"
kill "$mppid"
