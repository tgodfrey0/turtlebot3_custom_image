# Robot Image Builder

Build custom Yocto-based Linux images for robot companion computers.
Originally built for provisioning TurtleBot3 robots in a swarm; generalised to
support any single-board computer (Raspberry Pi, Jetson, etc.).

**Please send any feedback or questions to Toby Godfrey ([t.godfrey@soton.ac.uk](mailto:t.godfrey@soton.ac.uk)).**

## Prerequisites

- Ubuntu 22.04 or 24.04 (other supported distros: Fedora, Debian, openSUSE)
- ~50-100GB free disk space
- 8GB+ RAM recommended

### Install host packages

```bash
sudo apt install gawk wget git diffstat unzip texinfo gcc build-essential \
    chrpath socat cpio python3 python3-pip python3-pexpect python3-git \
    python3-jinja2 python3-subunit xz-utils debianutils iputils-ping \
    libacl1 liblz4-tool file locales zstd

sudo locale-gen en_US.UTF-8
```

### Or use pixi (recommended)

```bash
pixi install
```

## Quick Start (kas + build wrapper)

Install kas (e.g., pip install kas) and ensure git, python3 are available.

# Generate local.conf and build (recommended):
# - Use the build wrapper which generates conf/local.conf from template and runs kas
./build.sh --config configs/kas/build-config.yml --machine raspberrypi4-64

# Preview generated conf only:
./build.sh --config configs/kas/build-config.yml --machine raspberrypi4-64 --dry-run

# Interactive TUI (ratatui) to pick profile/options and export/build:
# Build and install binary to repo root:
# cd tools/kas-tui && ./install_and_place.sh
# Run the TUI binary from repo root:
# ./builder-tui --profile turtlebot3 --export --machine raspberrypi4-64
# or run in interactive mode (no --export) to use the full UI.

# Legacy: pixi-based workflow (kept for compatibility):
# pixi run setup-env
# source workspace/poky/oe-init-build-env workspace/build
# pixi run build configs/tb_jazzy.toml



## Configuration (kas)

The project now uses kas workspace configs in configs/kas/. Use the build wrapper
to generate conf/local.conf from conf/local.conf.template and run kas.

- configs/kas/generic.yml  — base kas workspace (poky, meta-openembedded, meta-raspberrypi, meta-robot)
- configs/kas/turtlebot3.yml — includes generic.yml and adds meta-ros
- The generic profile builds `robot-image` without TurtleBot3 or OpenCR.
- The TurtleBot3 profile builds `robot-image-ros`; OpenCR is enabled for that
  profile and can be disabled with `--opencr-enabled 0`.
- conf/local.conf.template — template; build.sh fills values and writes conf/local.conf
- tools/kas-tui — interactive TUI (ratatui) to pick profile, machine, extras, and export/build

Legacy TOML-based configs and the toml2conf tool have been removed. If you
relied on previous TOML configs, re-create the equivalent options using the
TUI or by editing conf/local.conf.template and configs/kas/*.yml.

## Output

- `tmp/deploy/images/<machine>/robot-image-<machine>.wic` — raw disk image
- `tmp/deploy/images/<machine>/robot-image-<machine>.wic.bmap` — block map

### Flashing

```bash
# Using bmaptool (recommended)
sudo bmaptool copy tmp/deploy/images/raspberrypi4-64/robot-image-*.wic /dev/sdX

# Using dd
sudo dd if=tmp/deploy/images/raspberrypi4-64/robot-image-*.wic of=/dev/sdX status=progress
```

**MAKE SURE YOU SELECT THE CORRECT DRIVE.**

## First Boot

On first boot, one-shot services run (each gated by a `.setup_*` marker file):

- **Hostname** — set to `<prefix>-<3 MAC octets>` (e.g. `tb3-ab-cd-ef`)
- **WiFi** — configured via netplan from stored JSON
- **Firewall** — SSH port opened in UFW
- **Tailscale** — prompted for auth key if not configured
- **Camera** — GPU memory configured (if enabled)
- **OpenCR** — motor controller firmware flashed (TurtleBot3 only)

Re-run any service by recreating its marker file and rebooting:
```bash
touch /home/robot/.setup_hostname
sudo reboot
```

## Architecture

```
layers/meta-robot/          # Custom Yocto layer
├── classes/                # Shared image classes
├── recipes-core/           # Core recipes (user, config, first-boot)
├── recipes-robot/          # Robot-specific recipes (turtlebot3)
├── recipes-connectivity/   # Network/VPN recipes
└── wic/                    # Disk layout templates

tools/toml2conf/            # Rust: TOML → local.conf translator
configs/                    # Robot build configurations
scripts/                    # Workspace setup scripts
conf/                       # Shared Yocto build settings
```

### Adding a New Robot

1. Create `layers/meta-robot/recipes-robot/<type>/` directory
2. Add recipes for robot-specific packages
3. Add first-boot scripts to `robot-firstboot` if needed
4. Set `[robot] type = "<type>"` in your TOML config
5. Build with `bitbake robot-image` or `bitbake robot-image-ros`

## Build Time

First build: **4-8 hours** (downloading and compiling from source).
Subsequent builds: **15-30 minutes** (with sstate-cache).

Yocto builds from source, not from pre-built packages. This gives full
control over the system but requires patience on first builds.
