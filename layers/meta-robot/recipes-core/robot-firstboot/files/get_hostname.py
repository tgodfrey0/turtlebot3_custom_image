import sys
import os
import time


def get_hostname() -> str:
    prefix = "robot"
    sep = "-"

    config_path = "/etc/robot-config/hostname_prefix"
    if os.path.exists(config_path):
        with open(config_path) as f:
            prefix = f.read().strip() or prefix

    mac_path = "/sys/class/net/wlan0/address"
    for _ in range(30):
        try:
            with open(mac_path) as f:
                mac = f.read().strip().replace(":", "")
            if len(mac) == 12:
                suffix = sep.join(mac[i:i + 2] for i in range(6, 12, 2)).upper()
                return f"{prefix}{sep}{suffix}"
        except OSError:
            pass
        time.sleep(1)

    raise RuntimeError("wlan0 MAC address is not available")


if __name__ == "__main__":
    print(get_hostname())
    sys.exit(0)
