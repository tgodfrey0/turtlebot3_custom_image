#!/bin/bash
set -eux -o pipefail

# Use environment variables with defaults
USERNAME="${USERNAME:-robot}"
USER_PASSWORD="${USER_PASSWORD:-turtlebot3}"

# Delete the default Ubuntu user
userdel -r ubuntu || echo "No default Ubuntu user"

# Create missing groups if they don't exist
for group in gpio ftp ssh; do
    if ! getent group "$group" > /dev/null; then
        groupadd "$group"
    fi
done

# Create a new user with the specified username
useradd \
    --create-home \
    --shell /bin/bash \
    --groups sudo,adm,dialout,video,gpio,ftp,ssh \
    "$USERNAME"

# Set password for the new user
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd

# Grant full sudo privileges without requiring a password
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"
chmod 0440 "/etc/sudoers.d/$USERNAME"

# Ensure ROS-related permissions (e.g., access to serial ports)
usermod -aG dialout "$USERNAME"

# Configure SSH access
grep -q "^AllowGroups" /etc/ssh/sshd_config || echo "AllowGroups ssh" >> /etc/ssh/sshd_config
usermod -aG ssh "$USERNAME"
systemctl restart sshd

# Configure FTP access
usermod -aG ftp "$USERNAME"

# Write network configuration if networks are provided
if [[ "$ADD_CONNECTION" == "true" ]] && [[ -n "${NETWORKS:-}" ]]; then
    echo "Writing network configuration..."
    mkdir -p /home/$USERNAME/.config
    echo "$NETWORKS" > /home/$USERNAME/.config/networks.json
    chown -R $USERNAME:$USERNAME /home/$USERNAME/.config
fi

echo "User '$USERNAME' created with full admin privileges and permissions for ROS, SSH, and FTP."
