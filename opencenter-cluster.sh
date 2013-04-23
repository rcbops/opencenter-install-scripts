#!/usr/bin/env bash
#               OpenCenter(TM) is Copyright 2013 by Rackspace US, Inc.
##############################################################################
#
# OpenCenter is licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.  This
# version of OpenCenter includes Rackspace trademarks and logos, and in
# accordance with Section 6 of the License, the provision of commercial
# support services in conjunction with a version of OpenCenter which includes
# Rackspace trademarks and logos is prohibited.  OpenCenter source code and
# details are available at: # https://github.com/rcbops/opencenter or upon
# written request.
#
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0 and a copy, including this
# notice, is available in the LICENSE file accompanying this software.
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the # specific language governing permissions and limitations
# under the License.
#
##############################################################################
#
set -e
set -u

function mangle_name() {
    server=${1:-}

    if [[ ${server} == ${CLUSTER_PREFIX}* ]]; then
        echo ${server}
    else
        echo ${CLUSTER_PREFIX}-${server}${CLUSTER_SUFFIX}
    fi
}

function get_image_type() {
    case $1 in
        "ubuntu") 
            IMAGE_TYPE="12.04 LTS"
            ;;
        "redhat")
            IMAGE_TYPE="Red Hat Enterprise Linux 6.1"
            ;;
        "centos")
            IMAGE_TYPE="CentOS 6.3"
            ;;
        "fedora")
            IMAGE_TYPE="Fedora 17"
            ;;
    esac
}

function ip_for() {
    server=$(mangle_name $1)

    ip=$($NOVA show ${server} | sed -En "/public network/ s/^.* ([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}).*$/\1/p")
    if [[ ${ip} =~ "." ]]; then
        echo ${ip}
    else
        echo ""
    fi
}

function wait_for_ip() {
    server=$(mangle_name $1)
    count=0

    max_count=20

    echo "Waiting for IPv4 on ${server}"

    while ! ( $NOVA list | grep ${server} | grep -q "ERROR" ); do
        ip=$(ip_for ${server});
        if [ "${ip}" == "" ]; then
            sleep 20
            count=$(( count + 1 ))
            if [ ${count} -gt ${max_count} ]; then
                echo "Aborting... too slow"
                exit 1
            fi
        else
            echo "Got IPv4: ${ip} for server: ${server}"
            break
        fi
    done

    if ( $NOVA list | grep ${server} | grep -q "ERROR" ); then
        echo "${server} in ERROR state, build failed"
        exit 1
    fi
}

function wait_for_ssh() {
    server=$(mangle_name $1)
    count=0
    max_ping=60  # 10 frigging minutes.
    max_count=18 # plus 3 min (*2) for ssh and getty

    wait_for_ip ${server}

    ip=$(ip_for ${server})

    echo "Waiting for ping on ${ip}"
    count=0
    while ( ! ping -c1 ${ip} > /dev/null 2>&1 ); do
        count=$(( count + 1 ))
        if [ ${count} -gt ${max_ping} ]; then
            echo "timeout waiting for ping"
            exit 1
        fi
        sleep 10
    done

    echo "Waiting for ssh on ${ip}"
    count=0
    while ( ! nc -w 1 ${ip} 22 | grep -q "SSH" ); do
        count=$(( count + 1 ))
        if [ ${count} -gt ${max_count} ]; then
            echo "timeout waiting for ssh"
            exit 1
        fi
        sleep 10
    done

    echo "SSH ready - waiting for valid login"
    count=0

    while ( ! ssh ${SSHOPTS} root@${ip} id | grep -q "root" ); do
        count=$(( count + 1 ))
        if [ ${count} -gt ${max_count} ]; then
            echo "timeout waiting for login"
            exit 1
        fi
        sleep 10
    done
    echo "Login successful"

    #redhat servers become accessible before setup is complete
    count=0
    while !( $NOVA list | grep ${server} | grep -q "ACTIVE" ); do
        count=$(( count + 1 ))
        if [ ${count} -gt ${max_count} ]; then
            echo "timeout waiting for server to become ACTIVE"
            exit 1
        fi
        sleep 10
    done
    echo "Server Active"
}

function setup_server_as() {
    server=$(mangle_name $1)
    as=$2
    ip=$(ip_for "opencenter-server")

    scriptName="install-dev"

    if ( $USE_PACKAGES ); then
        scriptName="install"
    fi

    scp ${SSHOPTS} ${BASEDIR}/${scriptName}.sh root@$(ip_for ${server}):/tmp

    # Upload screen.rc file if exists
    if [[ -f ${HOME}/.screenrc ]]; then
        echo "Setting up .screenrc file"
        scp ${SSHOPTS} ${HOME}/.screenrc root@$(ip_for ${server}):/root/.screenrc
    fi

    if !( $USE_PACKAGES ); then
        ssh ${SSHOPTS} root@$(ip_for ${server}) "cat /tmp/${scriptName}.sh | /bin/bash -s - ${verbose_string} ${rerun_string} --role=${as} --ip=${ip} ${git_dev_string}"
    else
        ssh ${SSHOPTS} root@$(ip_for ${server}) "cat /tmp/${scriptName}.sh | /bin/bash -s - ${verbose_string} ${rerun_string} --role=${as} --ip=${ip} --password=${OPENCENTER_PASSWORD}"
    fi
}

function credentials_check(){
    #only need to source nova env if not using supernova
    if [[ "$NOVA" == "nova" ]]
    then
        if [[ -f ${HOME}/csrc ]]; then
            source ${HOME}/csrc
        elif [[ -n $OS_USERNAME ]] && [[ -n $OS_TENANT_NAME ]] && [[ -n $OS_AUTH_URL ]] && [[ -n $OS_PASSWORD ]]; then
            echo "env variables already set"
        else
            echo "Please setup your cloud credentials file in ${HOME}/csrc"
            exit 1
        fi
    fi
}

function check_network(){
    if ( echo $network_value | egrep "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\/[0-9]{2}$" > /dev/null 2>&1 ); then
        PRIV_NETWORK=$network_value
        create_network
    elif [ "$network_value" == "--network" ] || [ "$network_value" == "-n" ]; then
        create_network
    elif ( $NOVA network-list | grep -q " ${network_value} " ); then
        priv_network_id=$($NOVA network-list | grep ${network_value} | awk '{print $2}')
        network_string="--nic net-id=${priv_network_id} ${network_string}"
    else
        echo "Invalid Network specified"
        usage
        exit 1
    fi
}

function boot_instances(){
    imagelist=$($NOVA image-list)
    flavorlist=$($NOVA flavor-list)

    image=$(echo "${imagelist}" | grep "${IMAGE_TYPE}" | head -n1 | awk '{ print $2 }')
    flavor_2g=$(echo "${flavorlist}" | grep 2GB | head -n1 | awk '{ print $2 }')
    flavor_4g=$(echo "${flavorlist}" | grep 4GB | head -n1 | awk '{ print $2 }')

    if !($ADD_CLIENTS)
    then
        if ( $NOVA list | egrep -q "${CLUSTER_PREFIX}-opencenter-(client|server|dashboard)[0-9]*${CLUSTER_SUFFIX} " ); then
            echo "${CLUSTER_PREFIX}- ${CLUSTER_SUFFIX} Prefix/Suffix combination is already in use, select another, or delete existing servers"
            exit 1
        fi
    fi

    if [[ -f ${key_location} ]]; then
        if ! ( $ADD_CLIENTS ); then
            $NOVA boot --flavor=${flavor_4g} --image ${image} ${network_string} --file /root/.ssh/authorized_keys=${key_location} $(mangle_name opencenter-server) > /dev/null 2>&1
            $NOVA boot --flavor=${flavor_2g} --image ${image} ${network_string} --file /root/.ssh/authorized_keys=${key_location} $(mangle_name opencenter-dashboard) > /dev/null 2>&1
        fi
        if ( $ADD_CLIENTS ); then
            if !( $NOVA list | grep -q $(mangle_name opencenter-server) ); then
                echo "There is no server with the specified prefix"
                usage
                exit 1
            fi
            echo "Adding additional Clients"
            get_network
            seq_count=$($NOVA list | sed -En "/${CLUSTER_PREFIX}-opencenter-client/ s/^.*${CLUSTER_PREFIX}-opencenter-client([0-9]*)${CLUSTER_SUFFIX} .*$/\1/p" | sort -rn | head -1 )
        fi
        for client in $(seq $((seq_count + 1)) $((CLIENT_COUNT + seq_count))); do
            $NOVA boot --flavor=${flavor_2g} --image ${image} ${network_string} --file /root/.ssh/authorized_keys=${key_location} $(mangle_name opencenter-client${client}) > /dev/null 2>&1
        done
    else
        echo "Please setup your specified key ${key_location} file for key injection to cloud servers "
        exit 1
    fi
}

function check_install_type(){
    ip=$(ip_for "opencenter-server")
    if ( nc -z ${ip} 8443 > /dev/null 2>&1 ); then
        USE_PACKAGES=true
        DASHBOARD_PORT=443
        server_port=8443
        DASHBOARD_PROTO=https
        echo "Server is listening on port 8443, using package install"
    elif ( nc -z ${ip} 8080 > /dev/null 2>&1 ); then
        echo "Server is listening on port 8080 using git install"
        USE_PACKAGES=false
        DASHBOARD_PORT=3000
        server_port=8080
        DASHBOARD_PROTO=http
    else
        echo "Server is not listening on 8080 or 8443, using specified setting"
    fi
}

function create_network(){
    if ( $NOVA network-list | grep -q ${CLUSTER_PREFIX}-net ); then
        echo "Network ${CLUSTER_PREFIX}-net already exists, delete and re-run or use different prefix"
        exit 1
    fi
    if !( $NOVA network-create ${CLUSTER_PREFIX}-net ${PRIV_NETWORK} > /dev/null 2>&1 ); then
        echo "Error creating Network - run $NOVA network-create ${CLUSTER_PREFIX}-net ${PRIV_NETWORK} to diagnose"
        exit 1
    fi
    priv_network_id=$($NOVA network-list | grep ${CLUSTER_PREFIX}-net | awk '{print $2}')
    network_string="--nic net-id=${priv_network_id} ${network_string}"
    echo "Network ${priv_network_id} created"
}

function get_network(){
    if ( $NOVA network-list | grep -q ${CLUSTER_PREFIX}-net ); then
        priv_network_id=$($NOVA network-list | grep ${CLUSTER_PREFIX}-net | awk '{print $2}')
        network_string="--nic net-id=${priv_network_id} ${network_string}"
    fi
}

function server_setup(){
    nodes=("")
    if !( $ADD_CLIENTS ); then
         wait_for_ssh "opencenter-server"
         nodes=(${nodes[@]} "opencenter-server")
         wait_for_ssh "opencenter-dashboard"
         nodes=(${nodes[@]} "opencenter-dashboard")
    fi
    for client in $(seq $((seq_count + 1)) $((CLIENT_COUNT + seq_count))); do
        if ( $NOVA list | grep -q "${CLUSTER_PREFIX}-opencenter-client${client}${CLUSTER_SUFFIX} " ); then
            wait_for_ssh "opencenter-client${client}"
            nodes=(${nodes[@]} "opencenter-client${client}")
        fi
    done

    for svr in ${nodes[@]}; do
        what=agent

        if [ "${svr}" == "opencenter-server" ]; then
            what=server
        fi

        if [ "${svr}" == "opencenter-dashboard" ]; then
            what=dashboard
        fi

        setup_server_as ${svr} ${what} > /tmp/$(mangle_name ${svr}).log 2>&1 &
        echo "Setting up server $(mangle_name ${svr}) as ${what} - logging status to /tmp/$(mangle_name ${svr}).log"
        PIDS["$!"]=${svr}
    done

    for pid in ${!PIDS[@]}; do
        echo "Waiting on pid ${pid}: $(mangle_name ${PIDS[${pid}]})"
        if [ ${pid} -ne 0 ]; then
            wait ${pid} > /dev/null 2>&1
            echo "Reaped ${pid}"
            if [ $? -ne 0 ]; then
                echo "Error setting up ${PIDS[${pid}]}"
            fi
        fi
    done
}


function usage() {
cat <<EOF
usage: $0 options

This script will install an OpenCenter Cluster.

OPTIONS:
  -h --help  Show this message
  -v --verbose  Verbose output
  -V --version  Output the version of this script

ARGUMENTS:
  -p= --prefix=<Cluster Prefix>
         Specify the name prefix for the cluster - default "c1"
  -s= --suffix=<Cluster Suffix>
         Specify a cluster suffix - default ".opencenter.com"
         Specifying "None" will use short name, e.g. just <Prefix>-opencenter-sever
  -c= --clients=<Number of Clients>
         Specify the number of clients to install, in conjunction with a server & dashboard - default 2
  -pass= --password=<Opencenter Server Password>
         Specify the Opencenter Server Password - only used for package installs - default "opencenter"
  -pkg --packages
         Install using packages
  -a --add-clients
         Add clients to Opencenter Cluster specified by Prefix
         Can't be used in conjunction with --rerun/-rr
         NB - If password was used for original cluster, password must be the same as existing cluster's password
  -n= --network=<CIDR>|<Existing network name>|<Existing network uuid>
         Setup a private cloud networks, will require "nova network-create" command - default 192.168.0.0/24
         You can specify an existing network name or network uuid
  -o= --os=[redhat | centos | ubuntu | fedora ]
         Specify the OS to install on the servers - default ubuntu
  -pk= --public-key=[location of key file]
         Specify the location of the key file to inject onto the cloud servers
  -rr --rerun
         Re-run the install scripts on the servers, rather than spin up new servers
         Can't be used in conjunction with --add-clients/-a
  -gb= --git-branch=<Git Branch>
         This will only work with non-package installs, specifies the git-branch to use.
         Defaults to "sprint"
  -gu= --git-user=<Git User>
         This will only work with non-package installs, specifies the user's repo to use.
         Defaults to "rcbops"
EOF
}


function display_version() {
cat <<EOF
$0 (version: $VERSION)
EOF
}

function licensing() {
   echo ""
   echo "
OpenCenter(TM) is Copyright 2013 by Rackspace US, Inc.
OpenCenter is licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.  This version of OpenCenter includes Rackspace trademarks and logos, and in accordance with Section 6 of the License, the provision of commercial support services in conjunction with a version of OpenCenter which includes Rackspace trademarks and logos is prohibited.  OpenCenter source code and details are available at: https://github.com/rcbops/opencenter/ or upon written request.
You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0 and a copy, including this notice, is available in the LICENSE.TXT file accompanying this software.
Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
"
}

function display_info() {
    server_ip=$(ip_for opencenter-server)
    auth_string=""
    if ( $USE_PACKAGES ); then
        auth_string="admin:$OPENCENTER_PASSWORD@"
    fi
    echo -e "\n*** COMPLETE ***\n"
    echo -e "Run \"export OPENCENTER_ENDPOINT=${DASHBOARD_PROTO}://${auth_string}${server_ip}:${server_port}\" to use the opencentercli"
    dashboard_ip=$(ip_for opencenter-dashboard)
    echo -e "Or connect to \"${DASHBOARD_PROTO}://${dashboard_ip}:${DASHBOARD_PORT}\" to manage via the opencenter-dashboard interface\n"
}

####################
# Global Variables #
#command to use for nova; read from environment or "nova" by default.
#This is so you can set NOVA="supernova env" before running the script.
NOVA=${NOVA:-nova}
VERSION=1.0.0
if [ -L $0 ]; then
    BASEDIR=$(dirname $(readlink $0))
else
    BASEDIR=$(dirname $0)
fi
declare -A PIDS
####################

####################
#  Flag Variables  #
RERUN=${RERUN:-false}
USE_PACKAGES=false
USE_NETWORK=false
PRIV_NETWORK="192.168.0.0/24"
CLUSTER_PREFIX="c1"
CLUSTER_SUFFIX=".opencenter.com"
CLIENT_COUNT=2
IMAGE_TYPE=${IMAGE_TYPE:-"12.04 LTS"}
ADD_CLIENTS=false
USE_NETWORK=false
OPENCENTER_PASSWORD=${OPENCENTER_PASSWORD:-"opencenter"}
seq_count=0
####################

####################
# Output Variables #
DASHBOARD_PORT=3000
DASHBOARD_PROTO=http
server_port=8080
####################

####################
#  Check ENV Vars  #
OS_AUTH_URL=${OS_AUTH_URL:-}
OS_TENANT_NAME=${OS_TENANT_NAME:-}
OS_USERNAME=${OS_USERNAME:-}
OS_PASSWORD=${OS_PASSWORD:-}
####################

####################
# Boot String Vars #
network_string="--nic net-id=00000000-0000-0000-0000-000000000000"
network_value=""
verbose_string=""
rerun_string=""
git_dev_string=""
key_location=${HOME}/.ssh/authorized_keys
SSHOPTS="-q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
####################

for arg in $@; do
    flag=$(echo $arg | cut -d "=" -f1)
    value=$(echo $arg | cut -d "=" -f2)
    case $flag in
        "--prefix" | "-p")
            if [ "$value" != "--prefix" ] && [ "$value" != "-p" ]; then
                CLUSTER_PREFIX=$value
            fi
            ;;
        "--suffix" | "-s")
            if [ "$value" != "--suffix" ] && [ "$value" != "-s" ]; then
                CLUSTER_SUFFIX=$value
                first_char=${CLUSTER_SUFFIX: 0:1}
                if [ $first_char != . ] && [ $CLUSTER_SUFFIX != "None" ]; then
                    CLUSTER_SUFFIX=."$CLUSTER_SUFFIX"
                elif [ $CLUSTER_SUFFIX = "None" ]; then
                    CLUSTER_SUFFIX=""
                fi
            fi
            ;;
        "--network" | "-n")
            USE_NETWORK=true
            network_value=$value
            ;;
        "--password" | "-pass")
            if [ "$value" != "--password" ] && [ "$value" != "-pass" ]; then
                OPENCENTER_PASSWORD=$value
            fi
            ;;
        "--clients" | "-c")
            if [ $value -eq $value 2>/dev/null ]; then
                CLIENT_COUNT=$value
            else
                usage
                exit 1
            fi
            ;;
        "--packages" | "-pkg")
            if [ "$git_dev_string" != "" ]; then
                echo "Can't use --git-user or --git-branch with Packages"
                echo "Ignoring --git-branch/--git-user setting"
                git_dev_string=""
            fi
            USE_PACKAGES=true
            DASHBOARD_PORT=443
            server_port=8443
            DASHBOARD_PROTO=https
            ;;
        "--os" | "-o")
            value=$(echo $value | tr "[:upper:]" "[:lower:]")
            if [ $value != "centos" ] && [ $value != "redhat" ] && [ $value != "fedora" ] && [ $value != "ubuntu" ]; then
                echo "Invalid OS type specified"
                usage
                exit 1
            else
                get_image_type $value
            fi
            ;;
        "--add-clients" | "-a")
            if ( $RERUN ); then
                echo "--rerun/-rr won't work with --add-clients/-a"
                exit 1
            fi
            ADD_CLIENTS=true
            ;;
        "--public-key" | "-pk")
            if [ "$value" != "--public-key" ] && [ "$value" != "-pk" ]; then
                if [ ${value:0:1} == "/" ]; then
                    key_location=$value
                elif [ ${value:0:1} == "~" ]; then
                    key_location="$HOME""${value:1}"
                else
                    key_location="$PWD""/""$value"
                fi
            fi
            ;;
        "--rerun" | "-rr")
            if ( $ADD_CLIENTS ); then
                echo "--rerun/-rr won't work with --add-clients/-a"
                exit 1
            fi
            RERUN=true
            rerun_string="--rerun"
            ;;
        "--git-branch" | "-gb")
            if [ "$value" != "--git-branch" ] && [ "$value" != "-gb" ]; then
                git_dev_string="$git_dev_string-gb=$value "
            fi
            if ( $USE_PACKAGES ); then
                echo "Can't use --git-branch with packages"
                echo "Ignoring --git-user setting and continuing"
                git_dev_string=""
            fi
            ;;
        "--git-user" | "-gu")
            if [ "$value" != "--git-user" ] && [ "$value" != "-gu" ]; then
                git_dev_string="$git_dev_string-gu=$value "
            fi
            if ( $USE_PACKAGES ); then
                echo "Can't use --git-user with packages"
                echo "Ignoring --git-user setting and continuing"
                git_dev_string=""
            fi
            ;;
        "--help" | "-h")
            usage
            exit 0
            ;;
        "--verbose" | "-v")
            VERBOSE=1
            verbose_string="-v"
            set -x
            ;;
        "--version" | "-V")
            display_version
            exit 0
            ;;
        *)
            echo "Invalid option $flag"
            usage
            exit 1
            ;;
    esac
done

credentials_check
if ( $USE_NETWORK ); then
    check_network
fi
if ( $RERUN ) || ( $ADD_CLIENTS); then
    check_install_type
fi
if ( $RERUN ); then
    if ( $NOVA list | egrep -q " ${CLUSTER_PREFIX}-opencenter-client[0-9]*${CLUSTER_SUFFIX} "); then
        CLIENT_COUNT=$($NOVA list | sed -En "/${CLUSTER_PREFIX}-opencenter-client/ s/^.*${CLUSTER_PREFIX}-opencenter-client([0-9]*)${CLUSTER_SUFFIX} .*$/\1/p" | sort -rn | head -1 )
    elif ( $NOVA list | egrep " ${CLUSTER_PREFIX}-opencenter-server${CLUSTER_SUFFIX} "); then
        CLIENT_COUNT=0
    else
        echo "There is no server with that prefix to re-run"
        exit 1
    fi
fi
if ( ! $RERUN ); then
    boot_instances
fi
server_setup
licensing
display_info

exit
