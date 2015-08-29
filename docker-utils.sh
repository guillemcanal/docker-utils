#!/bin/bash
set -e

usage()
{
    echo "Usage: docker-utils COMMAND DOCKER_MACHINE_NAME

Commands:
  create    Create a new machine with a NFS Share
  nfs       Create a NFS share on an existing docker machine
  start     Start a machine
  routing   Update the routing tables
  dns       Change the DNS domain used by your containers"
}

check_docker_machine()
{
    if [ `uname` != "Darwin" ]; then
        echo "This script is meant to be used on Mac OSX"
        exit 1
    fi

    if ! type docker-machine > /dev/null; then
        echo "You need to install the docker toolbox:"
        echo "https://www.docker.com/toolbox"
        exit 1
    fi
}

create()
{
    docker-machine create --driver virtualbox ${MACHINE_NAME}
    create_nfs
}

start()
{
    IS_RUNNING=$(docker-machine status $MACHINE_NAME &> /dev/null)
    if [[ $IS_RUNNING == "Running" ]]; then
       echo "$MACHINE_NAME is already running";
       exit
    fi

    docker-machine start $MACHINE_NAME
    eval $(docker-machine env $MACHINE_NAME)

    # Check if the NFS share is mounted
    if ! docker-machine ssh $MACHINE_NAME "mount | grep $HOME" &> /dev/null; then
        echo "Mounting NFS share..."
        docker-machine ssh $MACHINE_NAME "/var/lib/boot2docker/bootlocal.sh"
    fi

    # Check if we have a DNS container
    DNS_CONTAINER_ID=$(docker ps -a | grep iverberk/docker-spy | awk '{print $1}' | head -n1)
    if [ $DNS_CONTAINER_ID ]; then
        echo "Starting DNS container..."
        docker start $DNS_CONTAINER_ID
        update_dns_resolver $(get_current_dns_domain)
    fi

    update_routing_tables
}

create_nfs()
{
    echo "Creating NFS share..."

    # Check if the docker machine exist
    local MACHINE_STATUS=$(docker-machine status $MACHINE_NAME)
    if [[ $MACHINE_STATUS -ne "Running" ]]; then
        docker-machine start $MACHINE_NAME
    fi

    # Evaluate environement variables
    eval $(docker-machine env $MACHINE_NAME)

    # Check if the NFS Share is already configured
    local NFS_EXIST=$(docker-machine ssh $MACHINE_NAME "[ -e /var/lib/boot2docker/bootlocal.sh ] && grep nfs /var/lib/boot2docker/bootlocal.sh" 2> /dev/null) 
    if [[ "$NFS_EXIST" -ne "" ]]; then
        echo "NFS share already configured"
        exit
    fi

    echo "Removing virtualbox shared folder..."
    docker-machine stop ${MACHINE_NAME}
    VBoxManage sharedfolder remove ${MACHINE_NAME} --name Users &> /dev/null

    echo "Setting up the NFS share on Mac OSX..."
    echo "\"${HOME}\" -alldirs -mapall=$(whoami) -network 192.168.0.0 -mask 255.255.0.0" | sudo tee /etc/exports > /dev/null
    sudo nfsd checkexports && sudo nfsd restart

    echo "Setting up the NFS Share on the docker machine..."
    docker-machine start $MACHINE_NAME
    eval $(docker-machine env $MACHINE_NAME)
    
    local VBNET_NAME=$(VBoxManage showvminfo ${MACHINE_NAME} --machinereadable | grep hostonlyadapter | cut -d'"' -f2)
    local VBNET_IP=$(VBoxManage list hostonlyifs | grep "${VBNET_NAME}" -A 3 | grep IPAddress | cut -d ':' -f2 | xargs)
    local BOOTLOCAL_SH="#/bin/bash
    sudo mkdir -p ${HOME}
    sudo mount -t nfs -o noatime,soft,nolock,vers=3,udp,proto=udp,rsize=8192,wsize=8192,namlen=255,timeo=10,retrans=3,nfsvers=3 -v ${VBNET_IP}:${HOME} ${HOME}"

    docker-machine ssh ${MACHINE_NAME} "echo '${BOOTLOCAL_SH}' | sudo tee /var/lib/boot2docker/bootlocal.sh && sudo chmod +x /var/lib/boot2docker/bootlocal.sh && sh /var/lib/boot2docker/bootlocal.sh" > /dev/null

    local PROMPTED_DNS=$(prompt_dns_domain)
    create_dns_container $PROMPTED_DNS
    update_dns_resolver $PROMPTED_DNS

    update_routing_tables
}

# it allow us to resolve container IP from the host
update_routing_tables()
{
    echo "Updating your routing tables..."

    VB_IP=$(docker-machine ip ${MACHINE_NAME})

    # Remove old route 
    sudo route -n delete 172.17.0.0/16 &> /dev/null
    
    # Create route
    sudo route -n add 172.17.0.0/16 ${VB_IP}

    echo "------------------------------------"
    echo "SUCCESS                             "
    echo "Please execute the command below    "
    echo "------------------------------------"
    echo -e "eval \$(docker-machine env $MACHINE_NAME)"
}

# prompt a DNS domain to the user
prompt_dns_domain()
{
    local DNS_DOMAIN_DEFAULT="dev"

    read -p "Choose a DNS name (default: $DNS_DOMAIN_DEFAULT): " DNS_DOMAIN

    # Sanitize user input
    DNS_DOMAIN=${DNS_DOMAIN// /}
    DNS_DOMAIN=${DNS_DOMAIN//[^a-zA-Z0-9.]/}
    DNS_DOMAIN=${DNS_DOMAIN%.}
    DNS_DOMAIN=${DNS_DOMAIN#.}

    [[ $DNS_DOMAIN == "" ]] && DNS_DOMAIN=$DNS_DOMAIN_DEFAULT

    if [ ${#DNS_DOMAIN} -le 2 ]; then
        echo "'$DNS_NAME' is too short, your domain name must be at least 3 characters long"
        exit 1
    fi

    echo $DNS_DOMAIN
}

# return the hostname configured with the DNS container
get_current_dns_domain()
{
    var=$(docker inspect --format="{{index .Config.Env 0}}" dns); 
    echo ${var#*=}
}

create_dns_container()
{
    if [ "$#" -ne 1 ]; then
        echo "A DNS domain must be provided"
        exit 1
    fi

    DNS_DOMAIN=$1

    # check if the docker machine exist
    docker-machine status $MACHINE_NAME > /dev/null

    # remove DNS containers if exist
    local DNS_CONTAINERS=$(docker ps -a | grep iverberk/docker-spy | awk '{print $1}')
    if [ $DNS_CONTAINERS ]; then
        docker rm -f $DNS_CONTAINERS
    fi

    # start a new DNS container
    docker run -d --name dns -e DNS_DOMAIN="$DNS_DOMAIN" -p 172.17.42.1:53:53/udp -p 172.17.42.1:53:53 -v /var/run/docker.sock:/var/run/docker.sock iverberk/docker-spy
}

update_dns_resolver()
{
    if [ "$#" -ne 1 ]; then
        echo "A DNS domain must be provided"
        exit 1
    fi

    DNS_DOMAIN=$1

    # remove old resolver file that point to 172.17.42.1
    for f in /etc/resolver/*; do
      grep '172.17.42.1' $f &> /dev/null && sudo rm $f
    done

    echo "Exporting DNS resolver file in /etc/resolver/$DNS_DOMAIN ..."
    echo "nameserver 172.17.42.1" | sudo tee /etc/resolver/$DNS_DOMAIN > /dev/null
}

if [ "$#" -ne 2 ];then
    usage
    exit
fi

# the docker machine name
MACHINE_NAME=$2

check_docker_machine 

case "$1" in
    'create') 
        create 
        ;;
    'start') 
        start 
        ;;
    'nfs') 
        create_nfs
        ;;
    'routing') 
        update_routing_tables 
        ;;
    'dns')
        PROMPTED_DNS=$(prompt_dns_domain)
        create_dns_container $PROMPTED_DNS
        update_dns_resolver $PROMPTED_DNS
        ;;
    *)
        usage 
        ;;
esac





