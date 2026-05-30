#!/bin/bash

# Script to create user 'myuser' with password 'changeit' on Ubuntu 24
# Must be run as root or with sudo

set -e

USERNAME="dev"
PASSWORD="changeit" #"changeit"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root or with sudo."
  exit 1
fi

# Check if user already exists
if id "$USERNAME" &>/dev/null; then
  echo "User '$USERNAME' already exists. Skipping creation."
else
  # Create the user with a home directory and bash shell
  useradd -m -s /bin/bash "$USERNAME"
  echo "User '$USERNAME' created successfully."
fi

# Set the password
echo "$USERNAME:$PASSWORD" | chpasswd
echo "Password set for user '$USERNAME'."

# Grant sudo privileges by adding the user to the 'sudo' group
if id -nG "$USERNAME" | grep -qw sudo; then
  echo "User '$USERNAME' is already in the 'sudo' group. Skipping."
else
  usermod -aG sudo "$USERNAME"
  echo "User '$USERNAME' added to the 'sudo' group (sudoer)."
fi

echo "Done."
