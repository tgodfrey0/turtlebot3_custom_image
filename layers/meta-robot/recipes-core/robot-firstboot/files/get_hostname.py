import sys
import uuid
import os


def get_hostname() -> str:
    prefix = "robot"
    sep = "-"

    config_path = "/etc/robot-config/hostname_prefix"
    if os.path.exists(config_path):
        with open(config_path) as f:
            prefix = f.read().strip() or prefix

    try:
        mac = uuid.getnode()
        octets = [f"{(mac >> i) & 0xFF:02x}" for i in range(0, 48, 8)][::-1]
        suffix = sep.join(octets[3:6])
        return f"{prefix}{sep}{suffix}"
    except Exception:
        return f"{prefix}{sep}000000"


if __name__ == "__main__":
    print(get_hostname())
    sys.exit(0)
