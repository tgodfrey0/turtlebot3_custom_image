# Robot Plugins

Robot-specific setup lives in `robots/<robot_type>/` directories. The generic
core (Packer template, provisioner scripts, first-boot services) handles
everything common to any SBC robot image. Robot plugins add the specifics.

## How It Works

1. Your config sets `[robot] type = "<robot_type>"` (e.g. `turtlebot3`).
2. At build time, `build.py` detects `robots/<robot_type>/`, validates its
   layout, and copies it into the image at `/tmp/robot_plugin`.
3. The generic provisioner `scripts/50_robot_setup.sh` runs every
   `robots/<robot_type>/NN_*.sh` script in sorted (numeric-prefix) order.
4. After the build, `/tmp/robot_plugin` is removed from the image.

## Plugin Layout

```
robots/<robot_type>/
├── NN_description.sh    # Build-time setup steps, run in numeric order
└── setup_scripts/       # First-boot runtime scripts, copied into ~/setup_scripts
```

### Build-time steps: `NN_*.sh`

Each numeric-prefixed script runs **inside the chroot during image build** with
full root access (sourced by `50_robot_setup.sh`, in the order defined by the
prefix). Use them to install packages, build workspaces, create marker files,
enable first-boot services, and copy runtime scripts into
`/home/$USERNAME/setup_scripts/`.

Example ordering:
```
00_install_packages.sh
10_build_workspace.sh
20_setup_udev.sh
30_robot_env.sh
40_setup_opencr.sh
```

### Lexicographic naming: `NN_`

Order is defined by sorted filename, so use **zero-padded, fixed-width**
prefixes (`00_`, `10_`, `20_` ...) rather than variable-width ones. A prefix of
`2_` sorts after `19_`, so stick to a consistent width (commonly 2 digits).

### Runtime scripts: `setup_scripts/`

First-boot scripts that are *copied* (not run during build) live in the
`setup_scripts/` subdirectory. Your build steps copy them into
`/home/$USERNAME/setup_scripts/` and enable the corresponding service.

### Layout validation

`build.py` checks each plugin's layout and **raises an error** if a `.sh` file
is neither a `NN_*.sh` build step nor inside `setup_scripts/`. This catches
misnamed files (e.g. a stray `setup.sh` or `foo.sh` in the plugin root).
Build-time steps must be named `NN_*.sh`; runtime helpers must live in
`setup_scripts/`.

## Environment Variables Available in setup.sh

| Variable | Description |
|----------|-------------|
| `ROBOT_TYPE` | Robot type identifier |
| `ROBOT_MODEL` | Sub-model (e.g. `burger`, `waffle`) |
| `HOSTNAME_PREFIX` | Prefix for MAC-derived hostnames |
| `ROBOT_COMPONENTS` | JSON object of component toggles from `[robot.components]` |
| `BRINGUP_COMMAND` | Command to launch the robot |
| `USERNAME` | The configured username |
| `USER_PASSWORD` | The configured password |
| `ROS_ENABLED` | `true`/`false` |
| `ROS_DISTRO` | ROS distribution |
| `ROS_DOMAIN_ID` | ROS domain ID |
| `LIDAR` | LIDAR model |
| `TAILSCALE_ENABLED` | `true`/`false` |

## Runtime Config Files

Build-time scripts can write config for first-boot runtime scripts:

| File | Purpose |
|------|---------|
| `/etc/robot-user` | The configured username (written by 00_setup_user.sh) |
| `/etc/robot-config/robot_type` | Robot type |
| `/etc/robot-config/robot_model` | Robot sub-model |
| `/etc/robot-config/hostname_prefix` | Hostname prefix |
| `/etc/robot-config/lidar_model` | LIDAR model |
| `/etc/robot-config/bringup_command` | Command run by bringup.service |
| `/etc/robot-config/workspace_path` | Colcon workspace path |

## First-Boot Services

First-boot services live in `files/services/` and are generic. Robot plugins
enable them during build and create the corresponding `.setup_<name>` marker
file in `/home/$USERNAME/`. Each service only runs its script if the marker
file exists, then deletes it.

Example: to add a robot-specific first-boot action:
1. Create `robots/<type>/setup_mything.sh` that reads `$USERNAME` from
   `/etc/robot-user` and checks for `/home/$USERNAME/.setup_mything`.
2. Add a `mything_setup.service` to `files/services/`.
3. In `setup.sh`: `touch /home/$USERNAME/.setup_mything` and
   `systemctl enable mything_setup.service`.

## Component Toggles

Configs can define `[robot.components]` as a JSON object. For example:

```toml
[robot.components]
camera = true
opencr = false
```

The generic core uses `components.camera` to decide whether to run
`scripts/70_setup_camera.sh`. Other component keys are passed through to
`setup.sh` as the `ROBOT_COMPONENTS` JSON variable — the plugin decides how to
use them.
