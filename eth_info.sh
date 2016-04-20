#!/bin/bash

# Author: Maximilian Hristache
# License: MIT 
#
#This script can be used to retrieve information about the network devices
# which are installed in your system.
# Currently, for each network device it outputs:
#   - the PCI ID
#   - the interface name
#   - the NUMA node
#
# Note: If NUMA support is not enabled, it will output either 
#   -1 (The system does not support NUMA)
#   N/A (The system might support NUMA but the NUMA information is not defined for the device)


get_intf_name_and_type_from_pci_id ()
{
    # fetch the interface name and type from the PCI device id
    # input:
    # - $1: the PCI device ID, e.g. 0000:42:00.1
    #
    # output examples: 
    #   - net:eth0
    #   - uio:uio0
    #   - virtio:virtio0

    BASE_PATH=/sys/bus/pci/devices/$1/

    # look for 'net' (regular) device type
    if [ -d "$BASE_PATH/net/" ]; then
        IF_NAME=$(ls $BASE_PATH/net/)
        echo "net:$IF_NAME"

    # look for dpdk interface (uio)
    elif [ -d "$BASE_PATH/uio/" ]; then
        IF_NAME=$(ls $BASE_PATH/uio/)
        echo "uio:$IF_NAME"

    # check if it's a virtio device (virtual interface in a VM)
    else
        VIRTIO_INTF=$(ls $BASE_PATH | grep "^virtio")

        if [ $? -eq 1 ]; then
            # something went wrong and we could not find a virtio
            echo "N/A:N/A"
        else
            NEW_BASE_PATH=$BASE_PATH/$VIRTIO_INTF/

            # look for 'net' (regular) device type
            if [ -d "$NEW_BASE_PATH/net/" ]; then
                IF_NAME=$(ls $NEW_BASE_PATH/net/)
                echo "net:$IF_NAME"
        
            # look for dpdk interface (uio)
            elif [ -d "$NEW_BASE_PATH/uio/" ]; then
                IF_NAME=$(ls $NEW_BASE_PATH/uio/)
                echo "uio:$IF_NAME"
            fi
        fi
    fi
}


# find the PCI devices for the network cards
ETH_PCI_DEVS=$(lspci -Dvmmn | grep -B 1 "Class:.*0200$" | grep -v "Class:" | awk '{print $2}')

printf "\n%-15s  |  %-15s  |  %-4s\n" pci_device_id if_name numa
echo '--------------------------------------------'

for dev in $ETH_PCI_DEVS; do
    TYPE_AND_NAME_RAW=$(get_intf_name_and_type_from_pci_id $dev)

    # continue if the the device type and name could be retrieved
    if [ $? -eq 0 ]; then
        IFS=':' read -ra TYPE_AND_NAME <<< "$TYPE_AND_NAME_RAW"
        IF_TYPE=${TYPE_AND_NAME[0]}
        IF_NAME=${TYPE_AND_NAME[1]}
    
        # the file where we should find the NUMA info
        NUMA_FILE=/sys/class/$IF_TYPE/$IF_NAME/device/numa_node
    
        # the numa_node file might not exist (e.g. for virtio interfaces)
        if [ -f $NUMA_FILE ]; then
            NUMA=$(cat $NUMA_FILE)
        else
            NUMA="N/A"
        fi

        printf "%-15s  |  %-15s  |  %-4s\n" $dev $IF_NAME $NUMA
    fi
done

echo ""
