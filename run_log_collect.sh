#!/bin/bash

# Prompt for the sudo password
read -sp "Enter sudo password: " sudo_password
echo

# SSH into the remote server and run the script with sudo
ssh mystic@100.72.4.163 "echo '$sudo_password' | sudo -S bash -c 'curl -sSL https://raw.githubusercontent.com/DellProSupportGse/Tools/refs/heads/main/run_log_collect.sh -o /root/run_log_collect.sh && chmod 755 /root/run_log_collect.sh && bash /root/run_log_collect.sh'"
