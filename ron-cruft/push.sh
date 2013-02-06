#!/usr/bin/env bash

set -e

exec 99>/tmp/push.log
export BASH_XTRACEFD=99
set -x

trap on_exit EXIT

function on_exit() {
    if [ $? -ne 0 ]; then
        echo -e "\nERROR:\n"
        cat /tmp/push.log
        rm /tmp/push.log
    fi
}

declare -A PIDS

CLUSTER_PREFIX="c1"

if [ "x$1" != "x" ]; then
    CLUSTER_PREFIX=$1
fi

# we are assuming that we are sitting in one of the roush
# directories, and that roush-agent, roush, and roush-client
# are peers to the directory we are sitting in.

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

if [ ! -d ../roush-agent ] || [ ! -d ../roush ] || [ ! -d ../roush-client ]; then
    echo 'Not sitting in top level roush dir'
    exit 1
fi

nodes=$(nova list | cut -d'|' -f3 | grep "^ ${CLUSTER_PREFIX}" )

for node in ${nodes}; do
    ip=$(ip_for ${node})

    echo "Updating ${node}"

    echo " - killing roush services"
    ssh root@${ip} 'if (pgrep -f rous[h]); then pkill -f rous[h]; fi' >&99 2>&1
    echo " - setting git config"
    ssh root@${ip} 'git config --global receive.denyCurrentBranch ignore'

    for repo in ../roush-agent ../roush-client ../roush; do
        echo " - pushing $(basename ${repo})"
        pushd ${repo} >&99 2>&1
        git push root@${ip}:/root/$(basename ${repo}) HEAD:master >&99 2>&1
        ssh root@${ip} "cd /root/$(basename ${repo}) && git reset --hard" >&99 2>&1
        popd >&99 2>&1
    done

    # ssh root@${ip} /bin/bash -c "cd /root/roush-client; git reset --hard; cd /root/roush; git reset --hard; cd /root/roush-agent; git reset --hard" >&99 2>&1
    ssh root@${ip} /bin/bash -c 'cd /root/roush-client; cd /root/roush-client; ls; python setup.py install' >&99 2>&1

    echo " - Restarting roush-agent"
    ssh root@${ip} /bin/bash -c "cd roush-agent; cd roush-agent; PYTHONPATH=../roush screen -S roush-agent -d -m ./roush-agent.py -v -c ./local.conf"

    if [[ ${node} == ${CLUSTER_PREFIX}-roush-server ]]; then
        echo " - Restarting roush-server"
        ssh root@${ip} /bin/bash -c 'cd /root/roush; cd /root/roush; screen -S roush-server -d -m ./roush.py -v -c ./local.conf'
    fi
done
