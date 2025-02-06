# Custom TurtleBot3 Image

This repo provides a way to build a TurtleBot3 image with the necessary setup already complete. It works using Packer and is currently in the early stages of development. The aim of this is to make it easier to provision many TurtleBot3s for use in a swarm.

**Please send any feedback or questions to Toby Godfrey ([t.godfrey@soton.ac.uk](mailto:t.godfrey@soton.ac.uk)).**

## Prerequisites

This package uses Podman to run a container, so install Podman first.

## Usage

Creating the image is simple.

```bash
./build.sh <model>
```

This will output a `.img` with the name `tb3-image-<GIT TAG>.img`. The output image is automatically compressed once created. To prevent this run `./build.sh nocompress`.

`<model>` sets the type of TurtleBot3 for which you want to build the image. The options are:

- `waffle`
- `burger`

The `.img` file can then be flashed to the Raspberry Pi 4's MicroSD card.

```bash
sudo dd if=<CUSTOM_IMAGE>.img of=/dev/<RPI MicroSD> status=progress bs=32M
```

**MAKE SURE YOU SELECT THE CORRECT DRIVE -- the above command will wipe the drive!**

The address of the MicroSD card can be found with `sudo fdisk -l`.

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
- ~~Configures network details to allow for WiFi connection on boot (if the user has given the argument `addconnection`)~~

When booting for the first time:

- The hostname is changed to `turtlebot_XX_XX_XX` (where `XX_XX_XX` are the last three octets of the robot's MAC address)
  - This only runs if the file `/root/.setup_hostname` is present. If you play with the hostname and want to reset it touch that file and reboot and the service will run.
- The OpenCR board is configured
  - This runs at boot so the RPi should be connected to the OpenCR board during boot. This service also only runs if the file `/root/.setup_opencr` is present so if the board needs to be reconfigured just recreate that file and reboot.
- A firewall exception is added for SSH
  - This only runs if the file `/root/.setup_firewall` is present.
- The Pi Camera is enabled in the `/boot/firmware/` configuration file
  - This only runs if the file `/root/.setup_camera` is present.

### **_After booting the first time, the system must be restarted for several changes to take effect_**
