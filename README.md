# Custom TurtleBot3 Image

This repo provides a way to build a TurtleBot3 image with the necessary setup already complete. It works using Packer and is currently in the early stages of development. The aim of this is to make it easier to provision many TurtleBot3s for use in a swarm.

**Please send any feedback or questions to Toby Godfrey ([t.godfrey@soton.ac.uk](mailto:t.godfrey@soton.ac.uk)).**

## Prerequisites

- Python 3.11+
- Podman (for running the Packer container)

### Python Dependencies

Install the required Python packages:

```bash
pip install -r requirements.txt
```

## Usage

The build system uses TOML configuration files. Configuration files are stored in the `configs/` directory.

### Quick Start

1. Copy an example config and customise it:

```bash
cp configs/example.toml configs/my_robot.toml
# Edit configs/my_robot.toml with your settings
```

2. Run the build:

```bash
python build.py --config configs/my_robot.toml
```

### Configuration

The configuration file controls all build options:

- **Model**: Set `model.type` to `waffle` or `burger`
- **Network**: Optional `[[network]]` sections - use TOML array syntax (double brackets) to configure one or more WiFi networks
- **Compression**: Set `build.skip_compression` to `true` to skip `.xz` compression
- **Version**: Auto-detected from git tags, or set `image.version` manually

See `configs/example.toml` for a complete example with commented networks, and `configs/waffle_with_network.toml` for an example with multiple networks configured.

#### Multiple WiFi Networks

You can configure multiple WiFi networks using TOML array syntax:

```toml
[[network]]
ssid = "Network1"
password = "password1"

[[network]]
ssid = "Network2"
password = "password2"

[[network]]
ssid = "OpenNetwork"
# Leave password empty for open networks
```

All configured networks will be added to the netplan configuration and the robot will attempt to connect to them in order of priority.

### Build Options

```bash
# Basic build
python build.py --config configs/my_config.toml

# Dry run (validate config without building)
python build.py --config configs/my_config.toml --dry-run

# Build without confirmation prompt
python build.py --config configs/my_config.toml --yes

# Verbose output
python build.py --config configs/my_config.toml --verbose

# Custom Packer file
python build.py --config configs/my_config.toml --packer-file my_packer.json
```

### Output

The build outputs a `.img` file (and `.img.xz` if compression is enabled) with the name:
`{name}-{model}-image-{version}.img`

For example: `tb3-waffle_pi-image-v1.2.3.img`

### Flashing

The `.img` file can then be flashed to the Raspberry Pi 4's MicroSD card.

```bash
sudo dd if=<CUSTOM_IMAGE>.img of=/dev/<RPI MicroSD> status=progress
```

If the image has been compressed, it can still be flashed to the MicroSD card.

```bash
xz -dc <CUSTOM_IMAGE>.img.xz | sudo dd of=/dev/<RPI MicroSD> status=progress
```

**MAKE SURE YOU SELECT THE CORRECT DRIVE -- the above commands will wipe the drive!**

The address of the MicroSD card can be found with `sudo fdisk -l`.

You may wish to use something a bit more friendly than `dd`, such as [Balena Etcher](https://etcher.balena.io/).

### After Flashing

The image is 10GB to speed up creation and flashing. After, the image has been flashed to the MicroSD card, the partition size can be expanded to fill the rest of the drive.

This can be done using something like [GParted](https://gparted.org/).

You can then log into the Pi with the username `robot` and the password `turtlebot3`.

## Features

This script completes several tasks automatically.

When creating the image:

- Packages are updated
- A hostname `systemd` service is created
- QoL improvements (e.g. disable auto-sleep)
- Install ROS2 Humble Hawksbill
- Install the TurtleBot3 ROS packages
- Install the OpenCR packages
- Edit the firmware config to allow the Pi Camera to be used
- Enables SSH access
- Configures network details to allow for WiFi connection on boot (if the `[[network]]` sections are included in the config)
- Supports multiple WiFi networks for better connectivity options

When booting for the first time:

- The hostname is changed to `turtlebot_XX_XX_XX` (where `XX_XX_XX` are the last three octets of the robot's MAC address)
  - This only runs if the file `/home/robot/.setup_hostname` is present. If you play with the hostname and want to reset it touch that file and reboot and the service will run.
- The OpenCR board is configured
  - This runs at boot so the RPi should be connected to the OpenCR board during boot. This service also only runs if the file `/home/robot/.setup_opencr` is present so if the board needs to be reconfigured just recreate that file and reboot.
- A firewall exception is added for SSH
  - This only runs if the file `/home/robot/.setup_firewall` is present.
- The Pi Camera is enabled in the `/boot/firmware/` configuration file
  - This only runs if the file `/home/robot/.setup_camera` is present.

If you want to automatically launch the TurtleBot3 bringup package, enable the `bringup.service` service.

### **_After booting the first time, the system must be restarted for several changes to take effect_**
