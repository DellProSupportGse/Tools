#!/bin/bash

# Switch to root user (ensure you have the necessary privileges to do so)
if [ $(id -u) -ne 0 ]; then
    exec sudo -i "$0" "$@"
    exit $?
fi

# Commands to download and execute the script
curl -sSL https://raw.githubusercontent.com/DellProSupportGse/Tools/refs/heads/main/run_log_collect.sh -o /root/run_log_collect.sh && chmod 755 /root/run_log_collect.sh && bash /root/run_log_collect.sh
