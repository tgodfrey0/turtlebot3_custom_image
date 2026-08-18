# Robot Image Builder

Build custom Ubuntu disk images for robot single-board computers (SBCs) using
Packer. Works for any Pi-based robot — the common system setup is generic, and
robot-specific behaviour is provided by pluggable robot modules in `robots/`.

Originally built for provisioning many TurtleBot3 robots in a swarm; now
generalised. TurtleBot3 lives on as a reference robot plugin.

**Please send any feedback or questions to Toby Godfrey ([t.godfrey@soton.ac.uk](mailto:t.godfrey@soton.ac.uk)).**

## Prerequisites

- Python 3.11+
- Podman (for running the Packer container)
- bmap-tools (for faster flashing with bmaptool — `sudo apt install bmap-tools`)

### Python Dependencies

```bash
pip install -r requirements.txt
```

## Quick Start

```bash
cp configs/example.toml configs/my_robot.toml
# Edit configs/my_robot.toml with your settings
python build.py --config configs/my_robot.toml
```

### Install git hooks (recommended)

The pre-commit hook blocks commits containing Tailscale auth keys.

```bash
bash scripts/install_hooks.sh
```

## Configuration

Builds are controlled entirely by a TOML config file. See
`configs/example.toml` for a fully documented example.

Key sections:

| Section | Purpose |
|---------|---------|
| `[image]` | Image name, version, output directory, size |
| `[robot]` | Robot type (plugin selector), model, hostname prefix, bringup command |
| `[robot.components]` | Robot-specific feature toggles (e.g. `camera`) |
| `[[network]]` | WiFi networks (one `[[network]]` per AP, order = priority) |
| `[user]` | Username and password |
| `[ros]` | ROS2 distro + domain ID. **Omit this entire section to build without ROS2** |
| `[tailscale]` | Tailscale VPN config. Installed by default |
| `[source]` | Ubuntu base image URL. Auto-derived from ROS distro, or set explicitly |
| `[advanced]` | Packer builder image, verbose |

### Generic robot (no ROS, no robot plugin)

```toml
[image]
name = "plain_pi"

[robot]
type = "generic"
hostname_prefix = "node"

[source]
url = "https://cdimage.ubuntu.com/releases/24.04.3/release/ubuntu-24.04.3-preinstalled-server-arm64+raspi.img.xz"
checksum_url = "https://cdimage.ubuntu.com/releases/24.04.3/release/SHA256SUMS"
```

This produces a base image with: configured user, SSH, firewall, MAC-based
hostname, WiFi setup (if configured), and Tailscale — but no ROS and no
robot-specific packages.

### TurtleBot3 (reference plugin)

```toml
[image]
name = "tb3_swarm"

[robot]
type = "turtlebot3"
model = "burger"
hostname_prefix = "tb3"
bringup_command = "ros2 launch turtlebot3_bringup robot.launch.py"

[robot.components]
opencr = true
camera = true

[lidar]
model = "LDS-02"

[ros]
domain_id = 30
distro = "jazzy"

[[network]]
ssid = "MySwarmAP"
password = "password"
```

### Multiple WiFi Networks

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

The robot attempts to connect in order of priority.

### ROS Optional

ROS2 is installed only when the `[ros]` section is present. Without it, the
image ships no ROS packages and you must provide an explicit `[source]`
section.

- `[ros] distro` — `humble` (22.04), `iron` (22.04), `jazzy` (24.04), `rolling` (24.04)
- `[ros] domain_id` — valid range 0–101

### Tailscale

Tailscale is installed by default. Options:

| Setting | Default | Purpose |
|---------|---------|---------|
| `enabled` | `true` | Install Tailscale at all |
| `auth_key` | *(see below)* | Auto-authorize on first boot |
| `use_hostname` | `true` | Use the MAC-based hostname as the Tailscale node name |

**Do not put auth keys in config files.** Use the `TAILSCALE_AUTH_KEY`
environment variable instead (it takes precedence over config):

```bash
TAILSCALE_AUTH_KEY=tskey-auth-... python build.py --config configs/my_robot.toml
```

Keys look like `tskey-auth-...`. Generate them at
<https://login.tailscale.com/admin/settings/keys>. A `.githooks/pre-commit`
hook blocks commits that accidentally contain a key (install with
`bash scripts/install_hooks.sh`).

If no auth key is available, wait for first boot and run `tailscale up`
manually on the robot. If an auth key *is* provided, the image auto-joins your
tailnet on first boot.

## Build Options

```bash
# Basic build
python build.py --config configs/my_config.toml

# Dry run (validate config without building)
python build.py --config configs/my_config.toml --dry-run

# Build without confirmation prompt
python build.py --config configs/my_config.toml --yes

# Verbose output
python build.py --config configs/my_config.toml --verbose
```

The Packer template (`packer_build.json`) is generated automatically from your
config and saved next to the output image.

## Output

- `<name>-<robot>-image-<version>.img.xz` — compressed disk image
- `<name>-<robot>-image-<version>.img.xz.bmap` — block map for bmaptool

If compression is disabled (`skip_compression = true`), raw `.img` and
`.img.bmap` files are produced instead.

The `[robot]` label used in filenames is `type` or `type-model`
(e.g. `turtlebot3-burger`).

## Flashing

**Prerequisite:** `sudo apt install bmap-tools`

**Recommended — bmaptool (fastest):**

```bash
sudo bmaptool copy <CUSTOM_IMAGE>.img.xz /dev/<RPI MicroSD>
```

**Alternative — dd (slower, no bmap needed):**

```bash
xz -dc <CUSTOM_IMAGE>.img.xz | sudo dd of=/dev/<RPI MicroSD> status=progress
```

**MAKE SURE YOU SELECT THE CORRECT DRIVE -- the above commands will wipe the drive!**

Find the MicroSD address with `sudo fdisk -l`. You may prefer
[Balena Etcher](https://etcher.balena.io/).

### After Flashing

The image is 10GB to speed up creation and flashing. After flashing, expand
the partition to fill the drive using e.g. [GParted](https://gparted.org/).

Log in with the configured `[user]` credentials (defaults: `robot` /
`changeme`).

## Features

At build time:

- Base packages installed
- Configurable user created with passwordless sudo, SSH, and serial access
- SSH enabled, auto-sleep disabled
- Hostname service installed (MAC-derived, configurable prefix)
- ROS2 installed (optional, configurable distro)
- Tailscale installed (optional, auto-auth via env key)
- Robot plugin packages installed (e.g. TurtleBot3 ROS packages)
- WiFi configured (if `[[network]]` sections included)

On first boot (one-shot services, each gated on a `.setup_*` marker file):

- Hostname set to `<prefix>-<3 octets of MAC>` (e.g. `tb3-12-34-56`)
- WiFi configured via netplan
- Firewall exception added for SSH
- Robot-specific firmware flashed (e.g. TurtleBot3's OpenCR board)
- Tailscale authorized if an auth key was provided
- Optional: colcon workspace rebuilt

Re-run any one-shot setup by recreating its marker file
(e.g. `touch /home/robot/.setup_hostname`) and rebooting.

### **_After booting the first time, the system must be restarted for several changes to take effect_**

## Adding a New Robot

See `robots/README.md` for the plugin architecture. In short:

1. Create `robots/<type>/setup.sh` — runs at build time (sourced by
   `scripts/50_robot_setup.sh`).
2. Add any first-boot runtime scripts and copy them into
   `/home/$USERNAME/setup_scripts/`.
3. Set `[robot] type = "<type>"` in your config.

Available environment variables inside `setup.sh` (USERNAME, ROS_DISTRO,
ROBOT_COMPONENTS, etc.) are documented in `robots/README.md`.