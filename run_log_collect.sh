#!/bin/sh
[ "$(whoami)" != "root" ] && exec sudo -- "$0" "$@"
