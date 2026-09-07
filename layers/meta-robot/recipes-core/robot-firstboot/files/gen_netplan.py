import json
import sys

username = sys.argv[1]
networks_file = f"/home/{username}/.config/networks.json"
netplan_file = "/etc/netplan/50-wifi.yaml"

with open(networks_file) as f:
    networks = json.load(f)

with open(netplan_file, 'a') as f:
    for net in networks:
        ssid = net.get('ssid', '')
        password = net.get('password', '')
        if not ssid:
            continue
        if password:
            f.write(f'          "{ssid}":\n')
            f.write(f'            password: "{password}"\n')
        else:
            f.write(f'          "{ssid}":\n')
            f.write(f'            auth:\n')
            f.write(f'              key-management: none\n')

    f.write('        dhcp4: true\n')
    f.write('        dhcp6: true\n')
