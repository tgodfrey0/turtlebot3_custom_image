Adding a new robot type

Overview

This document describes how to add a new robot type (profile) to the kas/Yocto build and how to add robot-specific configuration and first-boot scripts.

1. Add a kas profile

- Create a new manifest in configs/kas, e.g. configs/kas/myrobot.yml. Base it on existing generic.yml or turtlebot3.yml.
- Include required layers (poky, meta-openembedded, meta-raspberrypi, meta-ros, and your meta-robot).
- Ensure the MACHINE and any BSP choices match the supported Yocto targets.

2. Add robot-specific recipes and files

- Put board- or robot-specific recipes under layers/meta-robot/recipes-robot/<robot-name>/.
  - Example: layers/meta-robot/recipes-robot/myrobot/myrobot-image.bb
- For first-boot tasks create or extend the robot-firstboot recipe files (layers/meta-robot/recipes-core/robot-firstboot/files/):
  - Add shell scripts (setup_<thing>.sh), Python helpers, and corresponding systemd unit files (.service).
  - Ensure robot-firstboot_1.0.bb lists the files in SRC_URI and installs them into /home/${ROBOT_USER}/setup_scripts and /etc/systemd/system.
  - Add marker touch files in robot-config recipe to trigger oneshot services on first boot.

3. Configuration support

- The recipe layers/meta-robot/recipes-core/robot-config writes build-time configuration into /etc/robot-config/. Add any new keys here and ensure they are written in do_install.
- Update conf/local.conf.template with any new variables you want the builder to set (e.g. MYROBOT_ENABLE=1).
- build.sh will set those variables when provided via --<name> flags; update build.sh parsing if new flags are needed.

4. TUI integration

- The TUI (tools/kas-tui) reads available profiles from configs/kas/ automatically. Add your manifest filename (without .yml) and the profile will appear in the "Profile" dropdown.
- To expose robot-specific checkboxes or fields, modify tools/kas-tui/src/main.rs to add fields, render them in the Parameters list, and include them in the args passed to build.sh (the TUI already collects common flags; follow the existing pattern).

5. First-boot services and testing

- Systemd unit files for first-boot are installed by robot-firstboot; check layers/meta-robot/recipes-core/robot-firstboot/files/*.service to see current units.
- To test without running a full kas build, run the TUI or build.sh with --no-build (export) to generate conf/local.conf and place output files under output/<image_name>/.
- To test services inside an image, mount the rootfs and inspect /etc/systemd/system and /etc/robot-config.

6. Naming and artefacts

- Output packaging: build.sh places per-image artefacts under output/<image_name>/ with:
  - image (main image file)
  - any auxiliary files (.bmap, .wic.bmap)
  - image-parameter_summary (build metadata and git short hash)

7. Best practises

- Keep first-boot scripts idempotent and guarded by marker files (the recipe touches .setup_* files and the scripts remove them after running).
- Avoid embedding secrets in summaries. The build pipeline masks passwords and omits auth keys from summaries by default; store auth keys in /etc/robot-config/tailscale_authkey if you choose to auto-join at first boot.
- Add unit tests or a small VM test to validate first-boot steps where feasible.

If you want, I can scaffold an example profile and a minimal recipe for your new robot type.
