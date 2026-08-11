# Netplan Static IP Installer

An interactive Bash script that configures a static IP address on Ubuntu LTS systems using [Netplan](https://netplan.io/). Instead of hand-editing YAML, the script walks you through interface selection, addressing, and DNS setup, then writes and applies the config for you.

## Features

- **Detects existing Netplan configs** in `/etc/netplan` and lets you overwrite one or create a fresh file
- **Lists available network interfaces** with their current state and MAC address
- **Accepts subnet mask or CIDR notation** (e.g. `255.255.255.0` or `24`) and normalizes it automatically
- **Backs up any existing config** before overwriting, timestamped for easy rollback
- **Validates and applies** the new config with `netplan generate` and `netplan apply`
- Locks down the resulting config file with `chmod 600`

## Requirements

- Ubuntu LTS (or another distro using Netplan with `networkd` as the renderer)
- Root privileges (`sudo`)
- `python3` available on the system (used internally to convert a dotted-decimal subnet mask to a CIDR prefix)

## Usage

```bash
sudo ./00-installer-static-ip.sh
```

You'll be prompted for:

1. **Netplan config file** – reuse an existing one or create `/etc/netplan/00-installer-config.yaml`
2. **Network interface** – chosen from a numbered list of detected interfaces
3. **Static IP address** – e.g. `192.168.1.50`
4. **Subnet mask or CIDR prefix** – e.g. `255.255.255.0` or `24`
5. **Gateway** – e.g. `192.168.1.1`
6. **DNS servers** – comma-separated, e.g. `1.1.1.1,8.8.8.8`

The script then shows a summary and asks for confirmation before writing anything to disk.

## Example

```
Available network interfaces:
  [1] eth0         state=UP       mac=52:54:00:12:34:56

Select the interface to configure [1-1]: 1
Enter static IP address (e.g. 192.168.1.50): 192.168.1.50
Enter subnet mask or CIDR prefix (e.g. 255.255.255.0 or 24): 24
Enter gateway (e.g. 192.168.1.1): 192.168.1.1
Enter DNS server(s), comma separated (e.g. 1.1.1.1,8.8.8.8): 1.1.1.1,8.8.8.8

Configuration summary:
  Interface : eth0
  Address   : 192.168.1.50/24
  Gateway   : 192.168.1.1
  DNS       : 1.1.1.1,8.8.8.8
  Config    : /etc/netplan/00-installer-config.yaml
Proceed with this configuration? [y/N]: y
```

Resulting Netplan config:

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: false
      addresses:
        - 192.168.1.50/24
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses: [1.1.1.1,8.8.8.8]
```

## Verifying the change

After the script finishes:

```bash
ip -brief addr show <interface>
```

## Notes & warnings

- Applying a bad network config to a **remote** machine (e.g. over SSH) can lock you out if the address, gateway, or interface name is wrong. Test on a console/local session first, or have out-of-band access (IPMI, hypervisor console, cloud provider serial console) available as a fallback.
- Existing config files are backed up as `<original-file>.bak.<timestamp>` in the same directory before being overwritten — check there if you need to roll back.
- The script targets systems using the `networkd` renderer; it will not work on distros without `netplan` installed.

## License

MIT (or update to match your project's license).
