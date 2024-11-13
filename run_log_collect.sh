# Define the user you want to switch to
TARGET_USER="root"

# Define the script URL
SCRIPT_URL="https://raw.githubusercontent.com/DellProSupportGse/Tools/refs/heads/main/log_collect.sh"

# Run the commands as the target user
sudo -u $TARGET_USER bash <<EOF
curl -sSL $SCRIPT_URL -o ./log_collect.sh && \
chmod 755 ./log_collect.sh && \
bash ./log_collect.sh
EOF
