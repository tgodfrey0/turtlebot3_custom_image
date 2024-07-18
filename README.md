# Custom TurtleBot3 Image

This repo provides a way to build a TurtleBot3 image with the necessary setup already complete. It works using Packer and is currently in the early stages of development. The aim of this is to make it easier to provision many TurtleBot3s for use in a swarm.

**Please send any feedback or questions to Toby Godfrey ([t.godfrey@soton.ac.uk](mailto:t.godfrey@soton.ac.uk)).**

## Usage

Creating the image is simple

```bash
./build.sh
```

The output image is automatically compressed once created. To prevent this run `./build.sh nocompress`.

The `.img` file can then be flashed to the Raspberry Pi 4's MicroSD card.

```bash

```

## Features

This script completes several tasks automatically.

When creating the image:

- Packages are updated
- A hostname `systemd` service is created
- QoL improvements (e.g. disable auto-sleep)
- Install ROS2 Humble Hawksbill
- Install the TurtleBot3 ROS packages
- Install the OpenCR packages

When booting for the first time:

- The hostname is changed to `turtlebot_XX_XX_XX` (where `XX_XX_XX` are the last three octets of the MAC address)
  - This only runs if the file `/root/.set_hostname` is present. If you play with the hostname and want to reset it touch that file and reboot and the service will run.
- The OpenCR board is configured
  - This runs at boot so the RPi should be connected to the OpenCR board during boot. This service also only runs if the file `/root/.setup_opencr` is present so if the board needs to be reconfigured just recreate that file and reboot.
