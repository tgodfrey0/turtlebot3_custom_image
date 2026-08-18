import sys
import uuid


def get_hostname() -> str:
    prefix = "tb3"
    sep = "-"
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
