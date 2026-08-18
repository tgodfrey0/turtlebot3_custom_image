#!/usr/bin/env python3
"""
Robot Image Builder

A Python-based build system for creating custom robot Ubuntu images.
Configuration is managed through TOML config files instead of CLI arguments.

Usage:
    python build.py --config configs/my_config.toml
    python build.py --config configs/my_config.toml --dry-run
    python build.py --config configs/my_config.toml -y

The [network] and [tailscale] sections are optional. Robot-specific setup
is handled via plugin scripts in the robots/ directory.
"""

import argparse
import hashlib
import os
import shutil
import subprocess
import sys
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional, List, Dict
import json


@dataclass
class NetworkConfig:
    """Configuration for a single WiFi network."""
    ssid: str = ""
    password: str = ""


@dataclass
class RobotConfig:
    """Robot-specific configuration."""
    type: str = "generic"
    model: str = ""
    hostname_prefix: str = "robot"
    bringup_command: str = ""
    components: Dict[str, bool] = field(default_factory=dict)


@dataclass
class TailscaleConfig:
    """Tailscale VPN configuration."""
    enabled: bool = True
    auth_key: str = ""
    use_hostname: bool = True


@dataclass
class LidarConfig:
    """LIDAR configuration."""
    model: str = ""


try:
    import tomli as tomllib
except ImportError:
    print("Error: tomli package is required. Install with: pip install tomli")
    sys.exit(1)

try:
    import tomli_w as tomllib_w
except ImportError:
    try:
        import tomllib as tomllib_w
    except ImportError:
        pass

ROS_DISTRO_UBUNTU_MAP: dict[str, str] = {
    "humble": "22.04",
    "iron": "22.04",
    "jazzy": "24.04",
    "rolling": "24.04",
}

# Full Ubuntu release version for URL construction (includes patch version)
ROS_DISTRO_UBUNTU_RELEASE_MAP: dict[str, str] = {
    "humble": "22.04.5",
    "iron": "22.04.5",
    "jazzy": "24.04.3",
    "rolling": "24.04.3",
}

VALID_ROS_DISTROS = set(ROS_DISTRO_UBUNTU_MAP.keys())

DEFAULT_UBUNTU_SOURCE_URL = (
    "https://cdimage.ubuntu.com/releases/22.04.5/release/"
    "ubuntu-22.04.5-preinstalled-server-arm64+raspi.img.xz"
)
DEFAULT_UBUNTU_CHECKSUM_URL = (
    "https://cdimage.ubuntu.com/releases/22.04.5/release/SHA256SUMS"
)


@dataclass
class BuildConfig:
    """Configuration for the build process."""
    # Image settings
    name: str = "robot"
    version: Optional[str] = None
    output_directory: str = "build"

    # Build options
    skip_compression: bool = False
    skip_sparse: bool = False

    # Network settings
    networks: List[NetworkConfig] = field(default_factory=list)

    # User settings
    username: str = "robot"
    user_password: str = "changeme"

    # Robot settings
    robot: RobotConfig = field(default_factory=RobotConfig)
    lidar: LidarConfig = field(default_factory=LidarConfig)

    # ROS settings (optional)
    ros_enabled: bool = True
    ros_domain_id: int = 0
    ros_distro: str = "humble"

    # Tailscale settings
    tailscale: TailscaleConfig = field(default_factory=TailscaleConfig)

    # Source image
    source_url: str = DEFAULT_UBUNTU_SOURCE_URL
    checksum_url: str = DEFAULT_UBUNTU_CHECKSUM_URL

    # Image size
    image_size: str = "10G"
    boot_size: str = "256M"

    # Advanced options
    packer_builder_image: str = "docker.io/mkaczanowski/packer-builder-arm:latest"
    verbose: bool = False

    # Computed fields
    computed_version: str = field(default="", init=False)
    add_connection: bool = field(default=False, init=False)
    ubuntu_version: str = field(default="", init=False)

    # Internal tracking (not user-configurable)
    _source_explicit: bool = field(default=False, init=False)


class BuildError(Exception):
    """Custom exception for build errors."""
    pass


def load_config(config_path: Path) -> BuildConfig:
    """Load configuration from TOML file."""
    if not config_path.exists():
        raise BuildError(f"Configuration file not found: {config_path}")

    with open(config_path, "rb") as f:
        data = tomllib.load(f)

    cfg = BuildConfig()

    # Parse image section
    if "image" in data:
        img = data["image"]
        cfg.name = img.get("name", cfg.name)
        cfg.version = img.get("version")
        cfg.output_directory = img.get("output_directory", cfg.output_directory)

    # Parse image size section
    if "image" in data and "size" in data["image"]:
        size = data["image"]["size"]
        cfg.image_size = size.get("total", cfg.image_size)
        cfg.boot_size = size.get("boot_partition", cfg.boot_size)

    # Parse robot section
    if "robot" in data:
        rob = data["robot"]
        cfg.robot.type = rob.get("type", cfg.robot.type)
        cfg.robot.model = rob.get("model", cfg.robot.model)
        cfg.robot.hostname_prefix = rob.get("hostname_prefix", cfg.robot.hostname_prefix)
        cfg.robot.bringup_command = rob.get("bringup_command", cfg.robot.bringup_command)
        if "components" in rob:
            cfg.robot.components = dict(rob["components"])

    # Backward compat: migrate [model] section to [robot]
    if "model" in data and "robot" not in data:
        model = data["model"]
        model_type = model.get("type", "")
        if model_type:
            print("Warning: [model] section is deprecated. Use [robot] section instead.")
            cfg.robot.type = "turtlebot3"
            cfg.robot.model = model_type

    # Parse build section
    if "build" in data:
        build = data["build"]
        cfg.skip_compression = build.get("skip_compression", cfg.skip_compression)
        cfg.skip_sparse = build.get("skip_sparse", cfg.skip_sparse)

    # Parse network section (optional)
    if "network" in data:
        networks_data = data["network"]
        if isinstance(networks_data, list):
            for net in networks_data:
                ssid = net.get("ssid")
                if ssid:
                    cfg.networks.append(NetworkConfig(
                        ssid=ssid,
                        password=net.get("password", "")
                    ))
        else:
            ssid = networks_data.get("ssid")
            if ssid:
                cfg.networks.append(NetworkConfig(
                    ssid=ssid,
                    password=networks_data.get("password", "")
                ))
        if cfg.networks:
            cfg.add_connection = True

    # Parse user section
    if "user" in data:
        usr = data["user"]
        cfg.username = usr.get("username", cfg.username)
        cfg.user_password = usr.get("password", cfg.user_password)

    # Parse lidar section (optional, robot-specific)
    if "lidar" in data:
        ldr = data["lidar"]
        cfg.lidar.model = ldr.get("model", cfg.lidar.model)

    # Parse ros section (optional - omit to disable ROS)
    if "ros" in data:
        cfg.ros_enabled = True
        ros = data["ros"]
        cfg.ros_domain_id = ros.get("domain_id", cfg.ros_domain_id)
        cfg.ros_distro = ros.get("distro", cfg.ros_distro)
    else:
        cfg.ros_enabled = False

    # Parse tailscale section (optional)
    if "tailscale" in data:
        ts = data["tailscale"]
        cfg.tailscale.enabled = ts.get("enabled", cfg.tailscale.enabled)
        cfg.tailscale.auth_key = ts.get("auth_key", cfg.tailscale.auth_key)
        cfg.tailscale.use_hostname = ts.get("use_hostname", cfg.tailscale.use_hostname)

    # Parse source section
    if "source" in data:
        cfg._source_explicit = True
        src = data["source"]
        cfg.source_url = src.get("url", cfg.source_url)
        cfg.checksum_url = src.get("checksum_url", cfg.checksum_url)

    # Parse advanced section
    if "advanced" in data:
        adv = data["advanced"]
        cfg.packer_builder_image = adv.get("packer_builder_image", cfg.packer_builder_image)
        cfg.verbose = adv.get("verbose", cfg.verbose)

    return cfg


def get_git_version() -> str:
    """Get version from git tags."""
    try:
        result = subprocess.run(
            ["git", "describe", "--tags", "--always"],
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return "unknown"


def check_sudo() -> bool:
    """Check if sudo is available without password prompt."""
    try:
        subprocess.run(
            ["sudo", "-n", "true"],
            capture_output=True,
            check=True
        )
        return True
    except subprocess.CalledProcessError:
        return False


def prompt_sudo() -> bool:
    """Prompt for sudo password."""
    print("sudo permissions are required for this build.")
    result = subprocess.run(["sudo", "-v"])
    return result.returncode == 0


def validate_config(cfg: BuildConfig) -> None:
    """Validate the build configuration."""
    if not cfg.ros_enabled and not cfg._source_explicit:
        raise BuildError(
            "ROS is disabled but no [source] section provided. "
            "When [ros] is omitted, you must specify [source] url and checksum_url."
        )

    if not cfg.ros_enabled and cfg.ros_distro not in VALID_ROS_DISTROS:
        raise BuildError(
            f"Invalid ROS distro: {cfg.ros_distro}. "
            f"Must be one of: {', '.join(sorted(VALID_ROS_DISTROS))}."
        )

    if cfg.ros_enabled:
        if cfg.ros_distro not in VALID_ROS_DISTROS:
            raise BuildError(
                f"Invalid ROS distro: {cfg.ros_distro}. "
                f"Must be one of: {', '.join(sorted(VALID_ROS_DISTROS))}."
            )
        if not (0 <= cfg.ros_domain_id <= 101):
            raise BuildError(
                f"Invalid ROS_DOMAIN_ID: {cfg.ros_domain_id}. Must be between 0 and 101."
            )


def compute_derived_values(cfg: BuildConfig) -> None:
    """Compute derived values from the configuration."""
    # Get version
    cfg.computed_version = cfg.version or get_git_version()

    # Compute Ubuntu version and source URLs from ROS distro (if ROS enabled)
    if cfg.ros_enabled:
        cfg.ubuntu_version = ROS_DISTRO_UBUNTU_MAP.get(cfg.ros_distro, "22.04")
        ubuntu_release = ROS_DISTRO_UBUNTU_RELEASE_MAP.get(cfg.ros_distro, "22.04.5")
        if not cfg._source_explicit:
            cfg.source_url = (
                f"https://cdimage.ubuntu.com/releases/{ubuntu_release}/release/"
                f"ubuntu-{ubuntu_release}-preinstalled-server-arm64+raspi.img.xz"
            )
            cfg.checksum_url = (
                f"https://cdimage.ubuntu.com/releases/{ubuntu_release}/release/SHA256SUMS"
            )
    else:
        cfg.ubuntu_version = "custom"


def prompt_missing_network_config(cfg: BuildConfig) -> None:
    """Prompt for missing network configuration if network section is present but empty."""
    if not cfg.add_connection:
        return

    if not cfg.networks:
        ssid = input("SSID: ").strip()
        if ssid:
            import getpass
            password = getpass.getpass("Password (Leave blank if N/A): ").strip() or ""
            cfg.networks.append(NetworkConfig(ssid=ssid, password=password))
            cfg.add_connection = True


def get_build_subdirectory(cfg: BuildConfig) -> Path:
    """Generate the build subdirectory path."""
    robot_label = cfg.robot.type
    if cfg.robot.model:
        robot_label = f"{cfg.robot.type}-{cfg.robot.model}"
    subdir_name = f"{cfg.name}-{robot_label}-{cfg.computed_version}"
    return Path(cfg.output_directory) / subdir_name


def get_robot_label(cfg: BuildConfig) -> str:
    """Get the robot label for output filenames."""
    if cfg.robot.model:
        return f"{cfg.robot.type}-{cfg.robot.model}"
    return cfg.robot.type


def save_config_to_build_dir(cfg: BuildConfig, build_dir: Path) -> None:
    """Save the complete configuration (including defaults) to the build directory."""
    config_dict = {
        "image": {
            "name": cfg.name,
            "version": cfg.version,
            "output_directory": cfg.output_directory,
            "size": {
                "total": cfg.image_size,
                "boot_partition": cfg.boot_size
            }
        },
        "robot": {
            "type": cfg.robot.type,
            "model": cfg.robot.model,
            "hostname_prefix": cfg.robot.hostname_prefix,
            "bringup_command": cfg.robot.bringup_command,
            "components": cfg.robot.components,
        },
        "build": {
            "skip_compression": cfg.skip_compression,
            "skip_sparse": cfg.skip_sparse
        },
        "network": [
            {"ssid": net.ssid, "password": net.password}
            for net in cfg.networks
        ] if cfg.networks else [],
        "user": {
            "username": cfg.username,
            "password": cfg.user_password
        },
        "lidar": {
            "model": cfg.lidar.model
        },
        "ros": {
            "enabled": cfg.ros_enabled,
            "domain_id": cfg.ros_domain_id,
            "distro": cfg.ros_distro
        } if cfg.ros_enabled else {"enabled": False},
        "tailscale": {
            "enabled": cfg.tailscale.enabled,
            "auth_key": "***" if cfg.tailscale.auth_key else "",
            "use_hostname": cfg.tailscale.use_hostname,
        },
        "source": {
            "url": cfg.source_url,
            "checksum_url": cfg.checksum_url
        },
        "advanced": {
            "packer_builder_image": cfg.packer_builder_image,
            "verbose": cfg.verbose
        },
        "_computed": {
            "computed_version": cfg.computed_version,
            "robot_label": get_robot_label(cfg),
            "add_connection": cfg.add_connection,
            "ubuntu_version": cfg.ubuntu_version
        }
    }

    config_path = build_dir / "build_config.toml"
    try:
        import tomli_w
        with open(config_path, "wb") as f:
            tomli_w.dump(config_dict, f)
    except ImportError:
        with open(config_path, "w") as f:
            f.write("# Auto-generated build configuration\n")
            f.write("# Includes all values (user-provided and defaults)\n\n")
            for section_name, section_data in config_dict.items():
                f.write(f"\n[{section_name}]\n")
                if isinstance(section_data, dict):
                    for k, v in section_data.items():
                        f.write(f"{k} = {v!r}\n")
                elif isinstance(section_data, list):
                    for item in section_data:
                        f.write(f"  {item!r}\n")


def display_config(cfg: BuildConfig) -> None:
    """Display the current configuration."""
    user_password_display = "*" * len(cfg.user_password)
    network_status = "enabled" if cfg.add_connection else "disabled"
    build_subdir = get_build_subdirectory(cfg)
    robot_label = get_robot_label(cfg)

    # Build network info string
    if cfg.networks:
        network_info = f"\nNETWORKS ({len(cfg.networks)} configured):"
        for i, net in enumerate(cfg.networks, 1):
            password_display = "*" * len(net.password) if net.password else "(none)"
            network_info += f"\n  {i}. SSID: {net.ssid}, Password: {password_display}"
    else:
        network_info = "\nNETWORKS: (none configured)"

    # ROS info
    if cfg.ros_enabled:
        ros_info = f"ROS_DISTRO: {cfg.ros_distro}\nROS_DOMAIN_ID: {cfg.ros_domain_id}"
    else:
        ros_info = "ROS: disabled"

    # Tailscale info
    ts_status = "enabled" if cfg.tailscale.enabled else "disabled"
    if cfg.tailscale.auth_key:
        ts_status += " (with auth key)"
    elif cfg.tailscale.enabled:
        ts_status += " (manual auth required)"

    # LIDAR info
    lidar_info = cfg.lidar.model if cfg.lidar.model else "(not set)"

    print(f"""
Configuration:
--------------
NAME: {cfg.name}
VERSION: {cfg.computed_version}
ROBOT_TYPE: {cfg.robot.type}
ROBOT_MODEL: {robot_label}
HOSTNAME_PREFIX: {cfg.robot.hostname_prefix}
LIDAR: {lidar_info}
{ros_info}
TAILSCALE: {ts_status}
UBUNTU_VERSION: {cfg.ubuntu_version}
USERNAME: {cfg.username}
USER_PASSWORD: {user_password_display}
SKIP_COMPRESSION: {cfg.skip_compression}
SKIP_SPARSE: {cfg.skip_sparse}
NETWORK: {network_status}{network_info}
OUTPUT_DIR: {cfg.output_directory}
BUILD_SUBDIR: {build_subdir}
""")


def confirm_build() -> bool:
    """Ask user to confirm the build."""
    response = input("Are these settings correct? (y/n): ").strip().lower()
    return response.startswith('y')


def check_output_file(cfg: BuildConfig, auto_yes: bool = False) -> None:
    """Check if output file already exists and prompt for overwrite."""
    build_subdir = get_build_subdirectory(cfg)
    robot_label = get_robot_label(cfg)
    pattern = f"{cfg.name}-{robot_label}-image-{cfg.computed_version}.img*"

    if build_subdir.exists():
        for f in build_subdir.glob(pattern):
            if auto_yes:
                print(f"Output file already exists: {f} - overwriting")
                f.unlink()
                return
            response = input(f"Output file already exists: {f}. Overwrite? (y/n): ").strip().lower()
            if response.startswith('y'):
                print("Overwriting...")
                f.unlink()
                return
            else:
                raise BuildError(f"Output file already exists: {f}")


def get_cache_dir() -> Path:
    """Get the cache directory for downloaded files."""
    cache_dir = Path(".cache")
    cache_dir.mkdir(exist_ok=True)
    return cache_dir


def download_file(url: str, dest: Path, timeout: int = 3600) -> None:
    """Download a file with progress reporting."""
    print(f"Downloading: {url}")
    print(f"Destination: {dest}")

    def report_progress(block_num: int, block_size: int, total_size: int) -> None:
        downloaded = block_num * block_size
        if total_size > 0:
            percent = min(downloaded * 100 / total_size, 100)
            print(f"\rProgress: {percent:.1f}% ({downloaded // 1024 // 1024}MB / {total_size // 1024 // 1024}MB)", end="", flush=True)

    urllib.request.urlretrieve(url, dest, reporthook=report_progress)
    print()  # New line after progress


def verify_checksum(file_path: Path, expected_checksum: str) -> bool:
    """Verify file checksum against expected value."""
    print(f"Verifying checksum...")
    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    computed = sha256_hash.hexdigest()
    return computed.lower() == expected_checksum.lower()


def get_expected_checksum(checksum_url: str, filename: str) -> str:
    """Fetch and parse checksum from URL."""
    print(f"Fetching checksum from: {checksum_url}")
    with urllib.request.urlopen(checksum_url, timeout=30) as response:
        checksums = response.read().decode('utf-8')

    for line in checksums.strip().split('\n'):
        parts = line.split()
        if len(parts) >= 2:
            checksum = parts[0]
            name = parts[1].lstrip('*')  # Remove leading * if present
            if filename in name or name in filename:
                return checksum

    raise BuildError(f"Could not find checksum for {filename} in {checksum_url}")


def download_source_image(cfg: BuildConfig) -> Path:
    """Download source image if not already cached, verify checksum, and return local path."""
    cache_dir = get_cache_dir()

    # Extract filename from URL
    url_path = Path(cfg.source_url)
    filename = url_path.name
    local_path = cache_dir / filename

    # Check if file already exists
    if local_path.exists():
        print(f"Found cached file: {local_path}")
        # Verify checksum even for cached files
        try:
            expected_checksum = get_expected_checksum(cfg.checksum_url, filename)
            if verify_checksum(local_path, expected_checksum):
                print("Checksum verified (cached file is valid)")
                return local_path
            else:
                print("Cached file checksum mismatch - re-downloading...")
                local_path.unlink()
        except Exception as e:
            print(f"Warning: Could not verify cached file: {e}")
            print("Proceeding with cached file...")
            return local_path

    # Download the file
    download_file(cfg.source_url, local_path)

    # Verify checksum
    try:
        expected_checksum = get_expected_checksum(cfg.checksum_url, filename)
        if not verify_checksum(local_path, expected_checksum):
            local_path.unlink()
            raise BuildError("Downloaded file checksum verification failed")
        print("Checksum verified")
    except Exception as e:
        print(f"Warning: Could not verify checksum: {e}")

    return local_path


def pull_packer_image(cfg: BuildConfig) -> None:
    """Pull the Packer builder Docker image."""
    print(f"Pulling Packer builder image: {cfg.packer_builder_image}")
    process = subprocess.Popen(
        ["sudo", "podman", "pull", cfg.packer_builder_image],
        preexec_fn=os.setpgrp
    )
    try:
        process.wait()
        if process.returncode != 0:
            raise subprocess.CalledProcessError(process.returncode, process.args)
    except KeyboardInterrupt:
        process.terminate()
        process.wait()
        raise


def run_packer_build(cfg: BuildConfig, packer_file: str, source_image_path: Path) -> None:
    """Run the Packer build."""
    build_subdir = get_build_subdirectory(cfg)

    # Get the checksum for the source image
    url_path = Path(cfg.source_url)
    filename = url_path.name
    try:
        expected_checksum = get_expected_checksum(cfg.checksum_url, filename)
        print(f"Using checksum: {expected_checksum}")
    except Exception as e:
        print(f"Warning: Could not fetch checksum: {e}")
        expected_checksum = ""

    cmd = [
        "sudo", "podman", "run", "--rm", "--privileged",
        "--pid=host",
        "-v", "/dev:/dev",
        "-v", f"{os.getcwd()}:/build",
        cfg.packer_builder_image,
        "build",
        "-var", f"NAME={cfg.name}",
        "-var", f"VERSION={cfg.computed_version}",
        "-var", f"SKIP_COMPRESSION={str(cfg.skip_compression).lower()}",
        "-var", f"SKIP_SPARSE={str(cfg.skip_sparse).lower()}",
        "-var", f"ROBOT_TYPE={cfg.robot.type}",
        "-var", f"ROBOT_MODEL={get_robot_label(cfg)}",
        "-var", f"HOSTNAME_PREFIX={cfg.robot.hostname_prefix}",
        "-var", f"ROBOT_COMPONENTS={json.dumps(cfg.robot.components)}",
        "-var", f"BRINGUP_COMMAND={cfg.robot.bringup_command}",
        "-var", f"ADD_CONNECTION={str(cfg.add_connection).lower()}",
        "-var", f"NETWORKS={json.dumps([{'ssid': net.ssid, 'password': net.password} for net in cfg.networks])}",
        "-var", f"USERNAME={cfg.username}",
        "-var", f"USER_PASSWORD={cfg.user_password}",
        "-var", f"ROS_ENABLED={str(cfg.ros_enabled).lower()}",
        "-var", f"ROS_DOMAIN_ID={cfg.ros_domain_id}",
        "-var", f"ROS_DISTRO={cfg.ros_distro}",
        "-var", f"TAILSCALE_ENABLED={str(cfg.tailscale.enabled).lower()}",
        "-var", f"TAILSCALE_AUTH_KEY={cfg.tailscale.auth_key}",
        "-var", f"TAILSCALE_USE_HOSTNAME={str(cfg.tailscale.use_hostname).lower()}",
        "-var", f"LIDAR={cfg.lidar.model}",
        "-var", f"BUILD_SUBDIR={build_subdir.name}",
        "-var", f"SOURCE_IMAGE_PATH={source_image_path}",
        "-var", f"IMAGE_CHECKSUM={expected_checksum}",
        "-var", f"IMAGE_SIZE={cfg.image_size}",
        "-var", f"BOOT_SIZE={cfg.boot_size}",
        packer_file
    ]

    if cfg.verbose:
        print(f"Running command: {' '.join(cmd)}")

    process = subprocess.Popen(cmd, preexec_fn=os.setpgrp)
    try:
        process.wait()
        if process.returncode != 0:
            raise subprocess.CalledProcessError(process.returncode, process.args)
    except KeyboardInterrupt:
        process.terminate()
        process.wait()
        raise


def main():
    parser = argparse.ArgumentParser(
        description="Build custom robot Ubuntu images using TOML configuration files.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Build with a config file
  python build.py --config configs/production.toml

  # Dry run to validate config
  python build.py --config configs/production.toml --dry-run

  # Build without confirmation prompt
  python build.py --config configs/production.toml -y

  # Verbose output
  python build.py --config configs/production.toml --verbose

Config File Structure:
  See configs/example.toml for a complete example.
  Robot-specific plugins go in robots/<robot_type>/.
        """
    )

    parser.add_argument(
        "--config", "-c",
        type=Path,
        required=True,
        help="Path to TOML configuration file"
    )

    parser.add_argument(
        "--packer-file", "-p",
        default="packer_ubuntu_server.json",
        help="Path to Packer configuration file (default: packer_ubuntu_server.json)"
    )

    parser.add_argument(
        "--dry-run", "-d",
        action="store_true",
        help="Show configuration without running build"
    )

    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable verbose output"
    )

    parser.add_argument(
        "--yes", "-y",
        action="store_true",
        help="Skip confirmation prompt"
    )

    args = parser.parse_args()

    try:
        # Load and validate configuration
        cfg = load_config(args.config)

        if args.verbose:
            cfg.verbose = True

        compute_derived_values(cfg)
        validate_config(cfg)

        # Handle network configuration (prompt for missing values if network section exists)
        prompt_missing_network_config(cfg)

        # Display configuration
        display_config(cfg)

        # Check for dry run
        if args.dry_run:
            print("\nDry run mode - not executing build.")
            sys.exit(0)

        # Confirm build
        if not args.yes and not confirm_build():
            print("Aborting operation.")
            sys.exit(0)

        print("\nProceeding with the build process...")

        # Create build subdirectory
        build_subdir = get_build_subdirectory(cfg)
        build_subdir.mkdir(parents=True, exist_ok=True)
        print(f"Build directory: {build_subdir}")

        # Save configuration to build directory (with all defaults)
        save_config_to_build_dir(cfg, build_subdir)
        print(f"Configuration saved to: {build_subdir}/build_config.toml")

        # Copy original config file to build directory
        original_config_dest = build_subdir / args.config.name
        shutil.copy2(args.config, original_config_dest)
        print(f"Original config copied to: {original_config_dest}")

        # Check output file doesn't exist
        check_output_file(cfg, auto_yes=args.yes)

        # Check sudo permissions
        if not check_sudo():
            if not prompt_sudo():
                raise BuildError("sudo permissions are required")

        # Download source image
        source_image_path = download_source_image(cfg)

        # Pull Packer image
        pull_packer_image(cfg)

        # Run build
        run_packer_build(cfg, args.packer_file, source_image_path)

        print("\nBuild completed successfully!")
        print(f"Output files in: {build_subdir}")

    except BuildError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(f"Command failed: {e}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\nBuild interrupted by user.")
        sys.exit(1)


if __name__ == "__main__":
    main()
