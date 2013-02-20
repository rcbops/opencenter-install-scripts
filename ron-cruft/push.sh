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

NOVA=${NOVA:-nova}

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
declare -A IPADDRS

SSHOPTS="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"

CLUSTER_PREFIX="c1"

if [ "x$1" != "x" ]; then
    CLUSTER_PREFIX=$1
fi

PUSH_PROJECT="roush-all"

if [ "x$2" != "x" ]; then
    PUSH_PROJECT=$2
else
    echo "No option specified, defaulting to 'roush-all'"
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

    ip=$($NOVA show ${server} | sed -En "/public network/ s/^.* ([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}).*$/\1/p")
    if [[ ${ip} =~ "." ]]; then
        echo ${ip}
    else
        echo ""
    fi
}

function repo_push() {
    repo=$1
    ip=$2
    echo " - pushing ${repo}"
    pushd ../${repo} >&99 2>&1
    git push root@${ip}:/root/${repo} HEAD:master >&99 2>&1
    ssh ${SSHOPTS} root@${ip} "cd /root/${repo} && git reset --hard" >&99 2>&1
    popd >&99 2>&1
}

function push_roush_agent() {
    if [ ! -d ../roush-agent ] || [ ! -d ../roush ]; then
        echo "Not sitting in top level roush dir or roush-agent/roush directory doesnt exist"
        exit 1
    fi

    ip=$1

    echo " - killing roush-agent services"
    ssh ${SSHOPTS} root@${ip} 'if (pgrep -f roush-agen[t]); then pkill -f roush-agen[t]; fi' >&99 2>&1
    repo="roush-agent"
    repo_push $repo $ip
    repo="roush"
    repo_push $repo $ip
    echo " - restarting roush-agent"
    ssh ${SSHOPTS} root@${ip} /bin/bash -c "cd roush-agent; cd roush-agent; PYTHONPATH=../roush screen -S roush-agent -d -m ./roush-agent.py -v -c ./local.conf"
}
function push_roush_server() {
    if [ ! -d ../roush ]; then
        echo 'Not sitting in top level roush dir or roush directory doesnt exist'
        exit 1
    fi

    ip=$1

    echo " - killing roush services"
    ssh ${SSHOPTS} root@${ip} 'if (pgrep -f roush.p[y]); then pkill -f roush.p[y]; fi' >&99 2>&1
    repo="roush"
    repo_push $repo $ip
    echo " - Restarting roush"
    ssh ${SSHOPTS} root@${ip} /bin/bash -c 'cd /root/roush; cd /root/roush; screen -S roush-server -d -m ./roush.py -v -c ./local.conf' >&99 2>&1
}

function push_roush_client() {
    if [ ! -d ../roush-client ]; then
       echo 'Not sitting in top level roush-client dir or roush-client directory doesnt exist'
       exit 1
    fi

    ip=$1

    repo="roush-client"
    repo_push $repo $ip
    echo " - installing roush-client"
    ssh ${SSHOPTS} root@${ip} /bin/bash -c 'cd /root/roush-client; cd /root/roush-client; ls; python setup.py install' >&99 2>&1
}

function push_ntrapy() {
    if [ ! -d ../ntrapy ]; then
        echo 'Not sitting in top level ntrapy dir or ntrapy directory doesnt exist'
        exit 1
    fi

    ip=$1

    repo="ntrapy"
    repo_push $repo $ip
    echo " - restarting ntrapy"
    ssh ${SSHOPTS} root@${ip} /bin/bash -c 'cd /root/ntrapy; cd /root/ntrapy; ./ntrapy' >&99 2>&1
}

nodes=$($NOVA list |grep -o "${CLUSTER_PREFIX}-[a-zA-Z0-9_-]*" )
for node in ${nodes}; do
    IPADDRS[$node]=$(ip_for ${node})
done

case "$PUSH_PROJECT" in
    "roush-all")
        for node in ${nodes}; do
            if [ "${node}" != "$(mangle_name 'ntrapy')" ]; then
                echo "Updating ${node}"
                echo " - setting git config for ${node} on IP : ${IPADDRS[$node]}"
                ssh ${SSHOPTS} root@${IPADDRS[$node]} 'git config --global receive.denyCurrentBranch ignore' >&99 2>&1
                push_roush_client ${IPADDRS[$node]}
                push_roush_agent ${IPADDRS[$node]}
                if [ "$node" == "$(mangle_name 'roush-server')" ]; then
                    push_roush_server ${IPADDRS[$node]}
                fi
            fi
        done
        ;;

    "roush")
        for node in ${nodes}; do
            if [ "$node" != "$(mangle_name 'ntrapy')" ]; then
                echo "Updating ${node}"
                echo " - setting git config for ${node} on IP: ${IPADDRS[$node]}"
                ssh ${SSHOPTS} root@${IPADDRS[$node]} 'git config --global receive.denyCurrentBranch ignore' >&99 2>&1
                # We have to restart roush_agent after the push.
                push_roush_agent ${IPADDRS[$node]}
                if [ "$node" == "$(mangle_name 'roush-server')" ]; then
                    push_roush_server ${IPADDRS[$node]}
                fi
            fi
        done
        ;;

    "roush-client")
        for node in ${nodes}; do
            if [ "$node" != "$(mangle_name 'ntrapy')" ]; then
                echo "Updating ${node}"
                echo " - setting git config for ${node} on IP : ${IPADDRS[$node]}"
                ssh ${SSHOPTS} root@${IPADDRS[$node]} 'git config --global receive.denyCurrentBranch ignore' >&99 2>&1
                push_roush_client ${IPADDRS[$node]}
            fi
        done
        ;;

    "roush-agent")
        for node in ${nodes}; do
            if [ "$node" != "$(mangle_name 'ntrapy')" ]; then
                echo "Updating ${node}"
                echo " - setting git config for ${node} on IP : ${IPADDRS[$node]}"
                ssh ${SSHOPTS} root@${IPADDRS[$node]} 'git config --global receive.denyCurrentBranch ignore' >&99 2>&1
                push_roush_agent ${IPADDRS[$node]}
            fi
        done
        ;;

    "ntrapy")
        for node in ${nodes}; do
            if [ "$node" == "$(mangle_name 'ntrapy')" ]; then
                echo "Updating ${node}"
                echo " - setting git config for ${node} on IP : ${IPADDRS[$node]}"
                ssh ${SSHOPTS} root@${IPADDRS[$node]} 'git config --global receive.denyCurrentBranch ignore' >&99 2>&1
                push_ntrapy ${IPADDRS[$node]}
            fi
        done
        ;;

    *)
        echo "Usage: push.sh <Cluster-Prefix> {roush-all | roush | roush-client | roush-agent | ntrapy}"
        exit 1
esac
