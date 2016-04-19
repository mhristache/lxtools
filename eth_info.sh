#!/bin/sh


strip ()
{
    sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/\\n*$//'
}


# find the PCI devices for the network cards
ETH_PCI_DEVS=$(lspci -Dvmmn | grep -B 1 "Class:\s*0200" | grep -v "Class:" | awk '{print $2}')



get_intf_name_from_pci_id ()
{

    # fetch the interface name from the PCI device id
    # input:
    # - $1: the PCI device ID, e.g. 0000:42:00.1

    BASE_PATH=/sys/bus/pci/devices/$1/

    # look for 'net' (regular) device type
    if [ -d "$BASE_PATH/net/" ]; then
        echo $(ls $BASE_PATH/net/)

    # look for dpdk interface (uio)
    elif [ -d "$BASE_PATH/uio/" ]; then
        echo $(ls $BASE_PATH/uio/)

    # check if it's a virtio (virtual interface in a VM)
    else
        VIRTIO_INTF=$(grep "^virtio" $BASE_PATH)

        if [ $? -eq 1 ]; then
            NEW_BASE_PATH=$BASE_PATH/$VIRTIO_INTF/

            # look for 'net' (regular) device type
            if [ -d "$NEW_BASE_PATH/net/" ]; then
                echo $(ls $NEW_BASE_PATH/net/)
        
            # look for dpdk interface (uio)
            elif [ -d "$NEW_BASE_PATH/uio/" ]; then
                echo $(ls $NEW_BASE_PATH/uio/)
            fi
        fi
    fi
}

printf "\n%-15s  |  %-7s  |  %-4s\n" pci_device_id if_name numa
echo '----------------------------------------'

for dev in $ETH_PCI_DEVS; do

    intf_name=$(get_intf_name_from_pci_id $dev)

    numa=$(cat /sys/class/net/$intf_name/device/numa_node)

    printf "%-15s  |  %-7s  |  %-4s\n" $dev $intf_name $numa
done
echo ""


