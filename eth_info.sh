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
#   - the interface speed
#   - the interface driver
#
# Note: If NUMA support is not enabled, it will output either 
#   '-1' (The system does not support NUMA)
#   '-'  (There is no NUMA information provided for the device)


path_basename ()
{
    # same role as python's os.path.basename, e.g.:
    # for input '/foo/bar' witll return 'bar'
    # input:
    #   - $1: the path
    echo ${1##*/}
}


get_intf_name_and_type_from_pci_id ()
{
    # fetch the interface name and type from the PCI device id
    # input:
    # - $1: the PCI device ID, e.g. 0000:42:00.1
    #
    # output: type:if_name:driver:status
    #   examples: 
    #    - net:eth0:igb:down
    #    - uio:uio0:igb_uio:up

    BASE_PATH="/sys/bus/pci/devices/$1/"

    # look for 'net' (regular) device type
    if [ -d "$BASE_PATH/net/" ]; then
        IF_TYPE="net"

    # look for dpdk interface (uio)
    elif [ -d "$BASE_PATH/uio/" ]; then
        IF_TYPE="uio"

    # check if it's a virtio device (virtual interface in a VM)
    else
        VIRTIO_INTF=$(ls $BASE_PATH | grep "^virtio")

        if [ $? -eq 1 ]; then

            # something went wrong and we could not find a virtio
            echo "-:-:-:-"
            return 0

        else
            BASE_PATH="${BASE_PATH}/$VIRTIO_INTF/"

            # look for 'net' (regular) device type
            if [ -d "$BASE_PATH/net/" ]; then
                IF_TYPE="net"
        
            # look for dpdk interface (uio)
            elif [ -d "$BASE_PATH/uio/" ]; then
                IF_TYPE="ui0"

            fi
        fi
    fi

    IF_NAME=$(ls $BASE_PATH/$IF_TYPE/)
    DRIVER=$(readlink $BASE_PATH/driver)

    if [ -f "$BASE_PATH/$IF_TYPE/$IF_NAME/carrier" ]; then

        # the carrier file is not readable if the interface is not enabled
        CARRIER=$(cat $BASE_PATH/$IF_TYPE/$IF_NAME/carrier 2> /dev/null)

        if [ ! $? -eq 0 ]; then
            STATE="admin_down"
        elif [ $CARRIER == 0 ]; then
            STATE="no_carrier"
        elif [ $CARRIER == 1 ]; then
            STATE="has_carrier"
        else
            STATE="unhandled"
        fi

    else
        STATE="unspecified"
    fi

    echo "$IF_TYPE:$IF_NAME:$(path_basename $DRIVER):$STATE"

}


# find the PCI devices for the network cards
ETH_PCI_DEVS=$(lspci -Dvmmn | grep -B 1 "Class:.*0200$" | grep -v "Class:" | awk '{print $2}')

printf "\n%-13s | %-15s | %-4s | %-11s | %-5s | %-16s\n" "pci_device_id" "if_name" "numa" "carrier" "speed" "driver"
echo '-----------------------------------------------------------------------'

for dev in $ETH_PCI_DEVS; do
    TYPE_AND_NAME_RAW=$(get_intf_name_and_type_from_pci_id $dev)

    # continue if the the device type and name could be retrieved
    if [ $? -eq 0 ]; then
        IFS=':' read -ra TYPE_AND_NAME <<< "$TYPE_AND_NAME_RAW"

        IF_TYPE=${TYPE_AND_NAME[0]}
        IF_NAME=${TYPE_AND_NAME[1]}
        DRIVER=${TYPE_AND_NAME[2]}
        STATE=${TYPE_AND_NAME[3]}
    
        # the file where we should find the NUMA info
        NUMA_FILE="/sys/class/$IF_TYPE/$IF_NAME/device/numa_node"
    
        # the numa_node file might not exist (e.g. for virtio interfaces)
        if [ -f $NUMA_FILE ]; then
            NUMA=$(cat $NUMA_FILE 2> /dev/null)
        else
            NUMA="-"
        fi

        # the file where we should find speed information
        SPEED_FILE="/sys/class/$IF_TYPE/$IF_NAME/speed"

        if [ -f $SPEED_FILE ]; then
            RAW_SPEED=$(cat $SPEED_FILE 2> /dev/null)
            
            if [ ! $? -eq 0 ]; then
                SPEED="-"
            else
                if [ $RAW_SPEED -lt 1000 ]; then
                    SPEED="${RAW_SPEED}M"
                else
                    SPEED="$((RAW_SPEED / 1000))G"
                fi
            fi
        else
            SPEED="-"
        fi

        printf "%-13s | %-15s | %-4s | %-11s | %-5s | %-16s\n" $dev $IF_NAME $NUMA $STATE $SPEED $DRIVER
    fi
done

echo ""
