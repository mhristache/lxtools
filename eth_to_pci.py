#!/usr/bin/env python

import subprocess
import os


# The PCI device class for ETHERNET devices
ETHERNET_CLASS = "0200"

# remote host
HOST = None


def check_output(args):
    """Run a command over ssh or locally and capture the output
    """
    ssh_args = []
    if HOST is not None:
        ssh_args = [
            '/usr/bin/ssh', '-o', 'StrictHostKeyChecking=no', 'root@%s' % HOST
        ]
    args = ssh_args + args
    with open(os.devnull, 'w') as DEVNULL:
        return subprocess.Popen(args, stdout=subprocess.PIPE,
                                stderr=DEVNULL).communicate()[0].decode('utf-8')


def get_interface_from_dev(dev_id, dev_type='net'):
    """Return the interface name for a PCI dev

    :param dev_id: the PCI device ID, e.g. 0000:42:00.1
    :param dev_type: the type of device: 'net' or 'uio'
    """
    # check for a unix interface name
    sys_path = "/sys/bus/pci/devices/%s/%s/" % (dev_id, dev_type)
    return check_output(['ls', sys_path]).strip()


def get_virtio_interface_from_dev(dev_id, dev_type='net'):
    """Return the interface name for a PCI dev for a virtio interface

    :param dev_id: the PCI device ID, e.g. 0000:42:00.1
    :param dev_type: the type of device: 'net' or 'uio'
    """
    # check for a unix interface name
    sys_path = "/sys/bus/pci/devices/%s/" % dev_id
    dirlist = check_output(['ls', sys_path]).strip().split()
    for f in dirlist:
        if f.startswith('virtio'):
            sys_path = "%s/%s/%s/" % (sys_path, f, dev_type)
            return check_output(['ls', sys_path]).strip()
    return ""


def get_ethernet_devices(lspci_print):
    """Parse the lspci print and return the list of ethernet devices pci id

    :param lspci_print: the output of lspci -Dvmmn
    :return: a list of ethernet PCI devices
    """
    result = []
    for grp in lspci_print.strip().split("\n\n"):
        ds = {}
        for line in grp.splitlines():
            parsed_line = line.partition(":\t")
            ds[parsed_line[0]] = parsed_line[2]
        if ds['Class'] == ETHERNET_CLASS:
            result.append(ds)
    return [x['Slot'] for x in result]


def ethernet_devices_dict():
    """ Return a dict with dev names and pci id. E.g: {eth2: 0000:01:00.2}
    """
    devices = {}
    lspci_print = check_output(["lspci", "-Dvmmn"])
    eth_devs = get_ethernet_devices(lspci_print)

    for dev in eth_devs:
        iface = get_interface_from_dev(dev)
        if iface == "":
            # check if the interface is using DPDK
            iface = get_interface_from_dev(dev, 'uio')
            if iface == "":
                # check if the interface is virtio (inside a VM)
                iface = get_virtio_interface_from_dev(dev)
                if iface == "":
                    # check if the interface is virtio and uses dpdk
                    iface = get_virtio_interface_from_dev(dev, 'uio')
        if iface != "":
            devices[iface] = dev
    return devices


if __name__ == "__main__":
    from optparse import OptionParser
    parser = OptionParser()
    parser.add_option(
        "--host",
        dest="host",
        help="the remote host to check"
    )
    parser.add_option(
        "-i", "--interfaces",
        dest="interfaces",
        help="a list of comma separated interface names to filter"
    )
    args, _ = parser.parse_args()

    if args.host is not None:
        HOST = args.host
    # fetch the interfaces details
    devices = ethernet_devices_dict()
    if args.interfaces is not None:
        ifaces = [x.strip() for x in args.interfaces.split(",")]
    else:
        ifaces = devices.keys()

    for i in ifaces:
        pci = devices.get(i)
        if pci is not None:
            print(pci + " -- " + i)
