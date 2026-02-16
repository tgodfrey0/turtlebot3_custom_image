#!/usr/bin/env python3
"""
TurtleBot3 Image Builder

A Python-based build system for creating custom TurtleBot3 Ubuntu images.
Configuration is managed through TOML config files instead of CLI arguments.

Usage:
    python build.py --config configs/my_config.toml
    python build.py --config configs/my_config.toml --dry-run
    python build.py --config configs/my_config.toml -y

The [network] section is optional. If included with an SSID, network connection
will be added automatically during the build.
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
from typing import Optional, List
import json


@dataclass
class NetworkConfig:
    """Configuration for a single WiFi network."""
    ssid: str = ""
    password: str = ""

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


@dataclass
class BuildConfig:
    """Configuration for the build process."""
    # Image settings
    name: str = "tb3"
    version: Optional[str] = None
    output_directory: str = "build"

    # Model settings
    model_type: str = "burger"

    # Build options
    skip_compression: bool = False

    # Network settings (list of networks, empty list means no networks)
    networks: List[NetworkConfig] = field(default_factory=list)

    # User settings (optional - defaults to robot/turtlebot3)
    username: str = "robot"
    user_password: str = "turtlebot3"

    # LIDAR settings (optional - defaults to LDS-02)
    lidar: str = "LDS-02"

    # Source image
    source_url: str = "https://cdimage.ubuntu.com/releases/22.04.5/release/ubuntu-22.04.5-preinstalled-server-arm64+raspi.img.xz"
    checksum_url: str = "https://cdimage.ubuntu.com/releases/22.04.5/release/SHA256SUMS"

    # Image size
    image_size: str = "10G"
    boot_size: str = "256M"

    # Advanced options
    packer_builder_image: str = "docker.io/mkaczanowski/packer-builder-arm:latest"
    verbose: bool = False

    # Computed fields
    computed_version: str = field(default="", init=False)
    opencr_model: str = field(default="", init=False)
    turtlebot3_model: str = field(default="", init=False)
    add_connection: bool = field(default=False, init=False)


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
    
    # Parse model section
    if "model" in data:
        model = data["model"]
        cfg.model_type = model.get("type", cfg.model_type)
    
    # Parse build section
    if "build" in data:
        build = data["build"]
        cfg.skip_compression = build.get("skip_compression", cfg.skip_compression)
    
    # Parse network section (optional)
    # Support both single [[network]] and multiple [[network]] entries
    if "network" in data:
        networks_data = data["network"]
        # Handle both single table and array of tables
        if isinstance(networks_data, list):
            for net in networks_data:
                ssid = net.get("ssid")
                if ssid:
                    cfg.networks.append(NetworkConfig(
                        ssid=ssid,
                        password=net.get("password", "")
                    ))
        else:
            # Single network table (backward compatibility)
            ssid = networks_data.get("ssid")
            if ssid:
                cfg.networks.append(NetworkConfig(
                    ssid=ssid,
                    password=networks_data.get("password", "")
                ))
        # Automatically enable add_connection if networks are configured
        if cfg.networks:
            cfg.add_connection = True

    # Parse user section (optional - defaults to robot/turtlebot3)
    if "user" in data:
        usr = data["user"]
        cfg.username = usr.get("username", cfg.username)
        cfg.user_password = usr.get("password", cfg.user_password)

    # Parse lidar section (optional - defaults to LDS-02)
    if "lidar" in data:
        ldr = data["lidar"]
        cfg.lidar = ldr.get("model", cfg.lidar)

    # Parse source section
    if "source" in data:
        src = data["source"]
        cfg.source_url = src.get("url", cfg.source_url)
        cfg.checksum_url = src.get("checksum_url", cfg.checksum_url)
    
    # Parse image size section
    if "image" in data and "size" in data["image"]:
        size = data["image"]["size"]
        cfg.image_size = size.get("total", cfg.image_size)
        cfg.boot_size = size.get("boot_partition", cfg.boot_size)
    
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
    if cfg.model_type not in ["waffle", "burger"]:
        raise BuildError(f"Invalid model type: {cfg.model_type}. Must be 'waffle' or 'burger'.")

    valid_lidars = ["LDS-01", "LDS-02", "LDS-03"]
    if cfg.lidar not in valid_lidars:
        raise BuildError(f"Invalid lidar model: {cfg.lidar}. Must be one of: {', '.join(valid_lidars)}.")


def compute_derived_values(cfg: BuildConfig) -> None:
    """Compute derived values from the configuration."""
    # Get version
    cfg.computed_version = cfg.version or get_git_version()
    
    # Set model values
    cfg.opencr_model = cfg.model_type
    if cfg.model_type == "waffle":
        cfg.turtlebot3_model = f"{cfg.model_type}_pi"
    else:
        cfg.turtlebot3_model = cfg.model_type


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
    """Generate the build subdirectory path based on image name, model, and version."""
    subdir_name = f"{cfg.name}-{cfg.turtlebot3_model}-{cfg.computed_version}"
    return Path(cfg.output_directory) / subdir_name


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
        "model": {
            "type": cfg.model_type
        },
        "build": {
            "skip_compression": cfg.skip_compression
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
            "model": cfg.lidar
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
            "opencr_model": cfg.opencr_model,
            "turtlebot3_model": cfg.turtlebot3_model,
            "add_connection": cfg.add_connection
        }
    }

    config_path = build_dir / "build_config.toml"
    try:
        import tomli_w
        with open(config_path, "wb") as f:
            tomli_w.dump(config_dict, f)
    except ImportError:
        # Fallback to writing TOML manually if tomli_w is not available
        with open(config_path, "w") as f:
            f.write("# Auto-generated build configuration\n")
            f.write("# Includes all values (user-provided and defaults)\n\n")
            f.write(f"name = {cfg.name!r}\n")
            f.write(f"version = {cfg.version!r}\n")
            f.write(f"output_directory = {cfg.output_directory!r}\n")
            f.write(f"computed_version = {cfg.computed_version!r}\n")
            f.write(f"model_type = {cfg.model_type!r}\n")
            f.write(f"skip_compression = {cfg.skip_compression}\n")
            f.write(f"add_connection = {cfg.add_connection}\n")
            f.write(f"networks_count = {len(cfg.networks)}\n")
            for i, net in enumerate(cfg.networks):
                f.write(f"network_{i}_ssid = {net.ssid!r}\n")
                f.write(f"network_{i}_password = {'***' if net.password else ''!r}\n")
            f.write(f"username = {cfg.username!r}\n")
            f.write(f"user_password = {'***' if cfg.user_password else None!r}\n")
            f.write(f"lidar = {cfg.lidar!r}\n")
            f.write(f"image_size = {cfg.image_size!r}\n")
            f.write(f"boot_size = {cfg.boot_size!r}\n")
            f.write(f"source_url = {cfg.source_url!r}\n")
            f.write(f"checksum_url = {cfg.checksum_url!r}\n")
            f.write(f"packer_builder_image = {cfg.packer_builder_image!r}\n")
            f.write(f"verbose = {cfg.verbose}\n")


def display_config(cfg: BuildConfig) -> None:
    """Display the current configuration."""
    user_password_display = "*" * len(cfg.user_password)
    network_status = "enabled" if cfg.add_connection else "disabled"
    build_subdir = get_build_subdirectory(cfg)

    # Build network info string
    if cfg.networks:
        network_info = f"\nNETWORKS ({len(cfg.networks)} configured):"
        for i, net in enumerate(cfg.networks, 1):
            password_display = "*" * len(net.password) if net.password else "(none)"
            network_info += f"\n  {i}. SSID: {net.ssid}, Password: {password_display}"
    else:
        network_info = "\nNETWORKS: (none configured)"

    print(f"""
Configuration:
--------------
NAME: {cfg.name}
VERSION: {cfg.computed_version}
MODEL: {cfg.model_type}
LIDAR: {cfg.lidar}
USERNAME: {cfg.username}
USER_PASSWORD: {user_password_display}
SKIP_COMPRESSION: {cfg.skip_compression}
NETWORK: {network_status}{network_info}
OUTPUT_DIR: {cfg.output_directory}
BUILD_SUBDIR: {build_subdir}
""")


def confirm_build() -> bool:
    """Ask user to confirm the build."""
    response = input("Are these settings correct? (y/n): ").strip().lower()
    return response.startswith('y')


def check_output_file(cfg: BuildConfig) -> None:
    """Check if output file already exists."""
    build_subdir = get_build_subdirectory(cfg)
    pattern = f"{cfg.name}-{cfg.turtlebot3_model}-image-{cfg.computed_version}.img*"
    
    if build_subdir.exists():
        for f in build_subdir.glob(pattern):
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
        ["podman", "pull", cfg.packer_builder_image],
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
        "-var", f"OPENCR_MODEL={cfg.opencr_model}",
        "-var", f"TURTLEBOT3_MODEL={cfg.turtlebot3_model}",
        "-var", f"ADD_CONNECTION={str(cfg.add_connection).lower()}",
        "-var", f"NETWORKS={json.dumps([{'ssid': net.ssid, 'password': net.password} for net in cfg.networks])}",
        "-var", f"USERNAME={cfg.username}",
        "-var", f"USER_PASSWORD={cfg.user_password}",
        "-var", f"LIDAR={cfg.lidar}",
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
        description="Build TurtleBot3 custom Ubuntu images using TOML configuration files.",
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
  The [network] section is optional. If included with an SSID, network
  connection will be added automatically. Remove or comment out the entire
  [network] section to skip network setup.

  See configs/example.toml for a complete example.
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
        default="packer_ubuntu_server_2204.json",
        help="Path to Packer configuration file (default: packer_ubuntu_server_2204.json)"
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
        check_output_file(cfg)
        
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
