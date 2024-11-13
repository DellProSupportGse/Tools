#!/bin/bash

# NAME: sgedit
# PATH: /mnt/e/bin
# DESC: Run gedit as sudo using $USER preferences
# DATE: June 17, 2018.

# Must not prefix with sudo when calling script
if [[ $(id -u) == 0 ]]; then
    zenity --error --text "You cannot call this script using sudo. Aborting."
    exit 99
fi

# Get user preferences before elevating to sudo
gsettings list-recursively | grep -i gedit | grep -v history | \
    grep -v docinfo | \
    grep -v virtual-root | grep -v state.window > /tmp/gedit.gsettings

sudoFunc () {

    # Must be running as sudo
    if [[ $(id -u) != 0 ]]; then
        zenity --error --text "Sudo password authentication failed. Aborting."
        exit 99
    fi

    # Get sudo's gedit preferences
    gsettings list-recursively | grep -i gedit | grep -v history | \
        grep -v docinfo | \
        grep -v virtual-root | grep -v state.window > /tmp/gedit.gsettings.root
    diff /tmp/gedit.gsettings.root /tmp/gedit.gsettings | grep '>' > /tmp/gedit.gsettings.diff
    sed -i 's/>/gsettings set/g; s/uint32 //g' /tmp/gedit.gsettings.diff
    chmod +x /tmp/gedit.gsettings.diff
    bash -x /tmp/gedit.gsettings.diff  # Display override setting to terminal
#    nohup gedit $@ &>/dev/null &
    nohup gedit -g 1300x840+1+1220 $@ &>/dev/null &
#              Set the X geometry window size (WIDTHxHEIGHT+X+Y).

}

FUNC=$(declare -f sudoFunc)
sudo -H bash -c "$FUNC; sudoFunc $*;"

exit 0
