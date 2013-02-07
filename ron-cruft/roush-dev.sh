#!/usr/bin/env bash

set -e

declare -A PIDS

CLUSTER_PREFIX="c1"

if [ "x$1" != "x" ]; then
    CLUSTER_PREFIX=$1
fi

function mangle_name() {
    server=$1

    if [[ ${server} == ${CLUSTER_PREFIX}* ]]; then
        echo ${server}
    else
        echo ${CLUSTER_PREFIX}-${server}
    fi
}

function ip_for() {
    server=$(mangle_name $1)

    ip=$(nova show ${server} | grep "public network" | sed -e  "s/.*[ ]\([0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/")

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

    while( true ); do
        ip=$(ip_for ${server});
        if [ "${ip}" == "" ]; then
            sleep 20
            count=$(( count + 1 ))
            if [ ${count} -gt ${max_count} ]; then
                echo "Aborting... to slow"
                exit 1
            fi
        else
            echo "Got IPv4: ${ip}"
            break
        fi
    done
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

    while ( ! ssh root@${ip} id | grep -q "root" ); do
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

    scp roush-server.sh root@$(ip_for ${server}):/tmp
    scp ${HOME}/.ssh/id_github root@$(ip_for ${server}):/root/.ssh/id_rsa
    scp known_hosts root@$(ip_for ${server}):/root/.ssh/known_hosts

    ssh root@$(ip_for ${server}) "cat /tmp/roush-server.sh | /bin/bash -s - ${as} ${ip}"
    ssh root@$(ip_for ${server}) 'bash -c "rm /root/.ssh/id_rsa"'
}


if [[ -f ~/csrc ]]; then
    source ~/csrc
else
    echo "Please setup your cloud credentials file in ~/csrc"
    exit 1
fi
#workon work

image=$(nova image-list | grep "12.04 LTS" | head -n1 | awk '{ print $2 }')
flavor_2g=$(nova flavor-list | grep 2GB | head -n1 | awk '{ print $2 }')
flavor_4g=$(nova flavor-list | grep 4GB | head -n1 | awk '{ print $2 }')

if ( nova list | grep -q $(mangle_name) ); then
    echo "$(mangle_name) prefix is already in use, select another, or delete existing servers"
    exit 1
fi

if [[ -f ${HOME}/.ssh/authorized_keys ]]; then
    nova boot --flavor=${flavor_4g} --image ${image} --file /root/.ssh/authorized_keys=${HOME}/.ssh/authorized_keys $(mangle_name roush-server) > /dev/null 2>&1
    nova boot --flavor=${flavor_2g} --image ${image} --file /root/.ssh/authorized_keys=${HOME}/.ssh/authorized_keys $(mangle_name roush-client1) > /dev/null 2>&1
    nova boot --flavor=${flavor_2g} --image ${image} --file /root/.ssh/authorized_keys=${HOME}/.ssh/authorized_keys $(mangle_name roush-client2) > /dev/null 2>&1
else
    echo "Please setup your ${HOME}/.ssh/authorized_keys file for key injection to cloud servers "
    exit 1
fi

wait_for_ssh "roush-server"
wait_for_ssh "roush-client1"
wait_for_ssh "roush-client2"

for svr in roush-server roush-client1 roush-client2; do
    what=client

    if [ "${svr}" == "roush-server" ]; then
        what=server
    fi

    setup_server_as ${svr} ${what} > /tmp/${svr}.log 2>&1 &
    PIDS["$!"]=${svr}
done

fail=0

for pid in ${!PIDS[@]}; do
    echo "Waiting on pid ${pid}"
    if [ ${pid} -ne 0 ]; then
        wait ${pid} > /dev/null 2>&1
        echo "Reaped ${pid}"
        if [ $? -ne 0 ]; then
            echo "Error setting up ${PIDS[${pid}]}"
            fail=1
        fi
    fi
done
