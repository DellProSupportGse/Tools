 if [ $(id -u) != 0 ]; then
     echo "You're not root"
     # elevate script privileges
 fi
