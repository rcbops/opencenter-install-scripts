#!/usr/bin/env bash
#
# Copyright 2012, Rackspace US, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
set -e
set -u

declare -A PIDS

#command to use for nova; read from environment or "nova" by default.
#This is so you can set NOVA="supernova env" before running the script.
NOVA=${NOVA:-nova}
RERUN=${RERUN:-false}
USE_PACKAGES=false
CLUSTER_PREFIX="c1"
CLIENT_COUNT=2
BASEDIR=$(dirname $0)
SSHOPTS="-q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
NTRAPY_PORT=3000

if [ "x$1" != "x" ]; then
    CLUSTER_PREFIX=$1
fi

if [ $# -ge 2 ]; then
    if [ $2 -eq $2 2>/dev/null ]; then
        CLIENT_COUNT=$2
    else
        echo "Usage: roush-dev.sh <Cluster-Prefix> <Number of Clients> {--packages}"
        exit 1
    fi
fi

if [ $# -ge 3 ]; then
    if [ "$3" == "--packages" ]; then
        USE_PACKAGES=true
        NTRAPY_PORT=80
    else
        echo "Usage: roush-dev.sh <Cluster-Prefix> <Nimber of Clients> {--packages}"
        exit 1
    fi
fi

function mangle_name() {
    server=${1:-}

    if [[ ${server} == ${CLUSTER_PREFIX}* ]]; then
        echo ${server}
    else
        echo ${CLUSTER_PREFIX}-${server}
    fi
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

    while ( ! $NOVA list | grep ${server} | grep -q "ERROR" ); do
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
}

function setup_server_as() {
    server=$(mangle_name $1)
    as=$2
    ip=$(ip_for "roush-server")

    if [[ ! -f ${HOME}/.ssh/id_github ]]; then
        echo "Please setup your github key in ${HOME}/.ssh/id_github"
        exit 1
    fi

    scriptName=roush-server
    if [ "$1" == "ntrapy" ]; then
        scriptName=ntrapy
    fi

    if [ $USE_PACKAGES ]; then
        scriptName="roush-server-packaged"
    fi

    scp ${SSHOPTS} ${BASEDIR}/${scriptName}.sh root@$(ip_for ${server}):/tmp
    scp ${SSHOPTS} ${HOME}/.ssh/id_github root@$(ip_for ${server}):/root/.ssh/id_rsa
    scp ${SSHOPTS} ${BASEDIR}/known_hosts root@$(ip_for ${server}):/root/.ssh/known_hosts

    ssh ${SSHOPTS} root@$(ip_for ${server}) "cat /tmp/${scriptName}.sh | /bin/bash -s - ${as} ${ip}"
    ssh ${SSHOPTS} root@$(ip_for ${server}) 'rm /root/.ssh/id_rsa'
}

instance_exists(){
    name=$(mangle_name $1)
    $NOVA list |grep -q $name
}

#only need to source nova env if not using supernova
if [[ "$NOVA" == "nova" ]]
then
    if [[ -f ${HOME}/csrc ]]; then
        source ${HOME}/csrc
    else
        echo "Please setup your cloud credentials file in ${HOME}/csrc"
        exit 1
    fi
fi



imagelist=$($NOVA image-list)
flavorlist=$($NOVA flavor-list)

image=$(echo "${imagelist}" | grep "12.04 LTS" | head -n1 | awk '{ print $2 }')
flavor_2g=$(echo "${flavorlist}" | grep 2GB | head -n1 | awk '{ print $2 }')
flavor_4g=$(echo "${flavorlist}" | grep 4GB | head -n1 | awk '{ print $2 }')

if ! $RERUN
then
    if ( $NOVA list | grep -q $(mangle_name) ); then
        echo "$(mangle_name) prefix is already in use, select another, or delete existing servers"
        exit 1
    fi
fi

if [[ -f ${HOME}/.ssh/authorized_keys ]]; then
    instance_exists roush-server || $NOVA boot --flavor=${flavor_4g} --image ${image} --file /root/.ssh/authorized_keys=${HOME}/.ssh/authorized_keys $(mangle_name roush-server) > /dev/null 2>&1
    for client in $(seq 1 $CLIENT_COUNT); do
        instance_exists roush-client${client} || $NOVA boot --flavor=${flavor_2g} --image ${image} --file /root/.ssh/authorized_keys=${HOME}/.ssh/authorized_keys $(mangle_name roush-client${client}) > /dev/null 2>&1
    done
    instance_exists ntrapy || $NOVA boot --flavor=${flavor_2g} --image ${image} --file /root/.ssh/authorized_keys=${HOME}/.ssh/authorized_keys $(mangle_name ntrapy) > /dev/null 2>&1
else
    echo "Please setup your ${HOME}/.ssh/authorized_keys file for key injection to cloud servers "
    exit 1
fi

nodes=("roush-server")
wait_for_ssh "roush-server"
for client in $(seq 1 $CLIENT_COUNT); do
    wait_for_ssh "roush-client${client}"
    nodes=(${nodes[@]} "roush-client${client}")
done
wait_for_ssh "ntrapy"
nodes=(${nodes[@]} "ntrapy")

for svr in ${nodes[@]}; do
    what=client

    if [ "${svr}" == "roush-server" ]; then
        what=server
    fi

    if [ "${svr}" == "ntrapy" ]; then
        what=ntrapy
    fi

    setup_server_as ${svr} ${what} > /tmp/$(mangle_name ${svr}).log 2>&1 &
    echo "Setting up server $(mangle_name ${svr}) as ${what} - logging status to /tmp/$(mangle_name ${svr}).log"
    PIDS["$!"]=${svr}
done

fail=0

for pid in ${!PIDS[@]}; do
    echo "Waiting on pid ${pid}: ${PIDS[${pid}]}"
    if [ ${pid} -ne 0 ]; then
        wait ${pid} > /dev/null 2>&1
        echo "Reaped ${pid}"
        if [ $? -ne 0 ]; then
            echo "Error setting up ${PIDS[${pid}]}"
            fail=1
        fi
    fi
done

server_ip=$(ip_for roush-server)
echo -e "\n*** COMPLETE ***\n"
echo -e "Run \"export ROUSH_ENDPOINT=http://${server_ip}:8080\" to use the roushcli"
ntrapy_ip=$(ip_for ntrapy)
echo -e "Or connect to \"http://${ntrapy_ip}:${NTRAPY_PORT}\" to manage via the ntrapy interface\n"
