import uuid

ROS_NAMESPACE_PREFIX: str = "tb3"  # Prefixed to the namespace, e.g. prefix_FF_FF_FF
ROS_NAMESPACE_SEPARATOR: str = (
    "-"  # Splits the prefix and the octets, e.g. for _ the ns is prefix_XX_XX_XX
)
ROS_NAMESPACE = f"{ROS_NAMESPACE_PREFIX}{ROS_NAMESPACE_SEPARATOR}{ROS_NAMESPACE_SEPARATOR.join((['{:02x}'.format((uuid.getnode() >> i) & 0xFF) for i in range(0, 48, 8)][::-1])[3:6])}"  # Each robot's namespace is the last 3 octets of its MAC address
print(ROS_NAMESPACE)
