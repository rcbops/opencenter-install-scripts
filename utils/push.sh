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

NOVA=${NOVA:-nova}
REPO_PATH="../"
exec 99>/tmp/push.log
export BASH_XTRACEFD=99
set -x
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

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

SSHOPTS="-q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
PUSHOPTS="${PUSHOPTS}"
CLUSTER_PREFIX="c1"

if [ "x$1" != "x" ]; then
    CLUSTER_PREFIX=$1
fi

PUSH_PROJECT="opencenter-all"

if [ "x$2" != "x" ]; then
    PUSH_PROJECT=$2
else
    echo "No option specified, defaulting to 'opencenter-all'"
fi

if [ $# -ge 3 ]; then
    REPO_PATH=$3
    last_char=${REPO_PATH: -1:1}
    if [ $last_char != / ]; then
        REPO_PATH="$REPO_PATH"/
    fi
    if [ ! -d ${REPO_PATH}opencenter-agent ] && [ ! -d ${REPO_PATH}opencenter ] && [ ! -d ${REPO_PATH}opencenter-client ] && [ ! -d ${REPO_PATH}opencenter-dashboard ]; then
        echo "No repo's in specified path"
        exit 1
    fi
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

    pushd ${REPO_PATH}${repo} >&99 2>&1
    if [ "$OC_SYNC" == "rsync" ]; then
        rsync -e "ssh ${SSHOPTS}" -C -av --delete --exclude='*.conf' --exclude='*.db' . root@${ip}:/root/${repo} >&99 2>&1
    else
        if [ -f ${SCRIPT_DIR}/GIT_SSH ]; then
            export GIT_SSH="${SCRIPT_DIR}/GIT_SSH"
        fi
        git push ${PUSHOPTS} root@${ip}:/root/${repo} HEAD:master >&99 2>&1
        ssh ${SSHOPTS} root@${ip} "cd /root/${repo} && git reset --hard" >&99 2>&1
    fi
    popd >&99 2>&1

}

function push_opencenter_agent() {
    if [ ! -d ${REPO_PATH}opencenter-agent ] || [ ! -d ${REPO_PATH}opencenter ]; then
        echo "Not sitting in top level opencenter dir or opencenter-agent/opencenter directory doesnt exist"
        exit 1
    fi

    ip=$1

    echo " - killing opencenter-agent services"
    ssh ${SSHOPTS} root@${ip} 'if (pgrep -f opencenter-agen[t]); then pkill -f opencenter-agen[t]; fi' >&99 2>&1
    repo="opencenter-agent"
    repo_push $repo $ip
    repo="opencenter"
    repo_push $repo $ip
    echo " - restarting opencenter-agent"
    ssh ${SSHOPTS} root@${ip} /bin/bash -c "cd opencenter-agent; cd opencenter-agent; PYTHONPATH=../opencenter screen -S opencenter-agent -d -m ./opencenter-agent.py -v -c ./local.conf"
}
function push_opencenter_server() {
    if [ ! -d ${REPO_PATH}opencenter ]; then
        echo 'Not sitting in top level opencenter dir or opencenter directory doesnt exist'
        exit 1
    fi

    ip=$1

    echo " - killing opencenter services"
    ssh ${SSHOPTS} root@${ip} 'if (pgrep -f opencenter.p[y]); then pkill -f opencenter.p[y]; fi' >&99 2>&1
    repo="opencenter"
    repo_push $repo $ip
    echo " - Restarting opencenter"
    ssh ${SSHOPTS} root@${ip} /bin/bash -c 'cd /root/opencenter; cd /root/opencenter; screen -S opencenter-server -d -m ./opencenter.py -v -c ./local.conf' >&99 2>&1
}

function push_opencenter_client() {
    if [ ! -d ${REPO_PATH}opencenter-client ]; then
       echo 'Not sitting in top level opencenter-client dir or opencenter-client directory doesnt exist'
       exit 1
    fi

    ip=$1

    repo="opencenter-client"
    repo_push $repo $ip
    echo " - installing opencenter-client"
    ssh ${SSHOPTS} root@${ip} /bin/bash -c 'cd /root/opencenter-client; cd /root/opencenter-client; ls; python setup.py install' >&99 2>&1
}

function push_opencenter_dashboard() {
    if [ ! -d ${REPO_PATH}opencenter-dashboard ]; then
        echo 'Not sitting in top level opencenter-dashboard dir or opencenter-dashboard directory doesnt exist'
        exit 1
    fi

    ip=$1

    repo="opencenter-dashboard"
    repo_push $repo $ip
    echo " - restarting opencenter-dashboard"
    ssh ${SSHOPTS} root@${ip} '/bin/bash -c "source /root/.profile;cd /root/opencenter-dashboard; make publish; ./dashboard"' >&99 2>&1
}

nodes=$($NOVA list |grep -o "${CLUSTER_PREFIX}-[a-zA-Z0-9_-]*" )
for node in ${nodes}; do
    IPADDRS[$node]=$(ip_for ${node})
done

case "$PUSH_PROJECT" in
    "opencenter-all")
        for node in ${nodes}; do
                echo "Updating ${node}"
                echo " - setting git config for ${node} on IP : ${IPADDRS[$node]}"
                ssh ${SSHOPTS} root@${IPADDRS[$node]} 'git config --global receive.denyCurrentBranch ignore' >&99 2>&1
                if [ "${node}" = "$(mangle_name 'opencenter-dashboard')" ]; then
                    push_opencenter_dashboard ${IPADDRS[$node]}
                else
                    push_opencenter_client ${IPADDRS[$node]}
                    push_opencenter_agent ${IPADDRS[$node]}
                    if [ "$node" == "$(mangle_name 'opencenter-server')" ]; then
                        push_opencenter_server ${IPADDRS[$node]}
                    fi
                fi
        done
        ;;

    "opencenter")
        for node in ${nodes}; do
            if [ "$node" != "$(mangle_name 'opencenter-dashboard')" ]; then
                echo "Updating ${node}"
                echo " - setting git config for ${node} on IP: ${IPADDRS[$node]}"
                ssh ${SSHOPTS} root@${IPADDRS[$node]} 'git config --global receive.denyCurrentBranch ignore' >&99 2>&1
                # We have to restart opencenter_agent after the push.
                push_opencenter_agent ${IPADDRS[$node]}
                if [ "$node" == "$(mangle_name 'opencenter-server')" ]; then
                    push_opencenter_server ${IPADDRS[$node]}
                fi
            fi
        done
        ;;

    "opencenter-client")
        for node in ${nodes}; do
            if [ "$node" != "$(mangle_name 'opencenter-dashboard')" ]; then
                echo "Updating ${node}"
                echo " - setting git config for ${node} on IP : ${IPADDRS[$node]}"
                ssh ${SSHOPTS} root@${IPADDRS[$node]} 'git config --global receive.denyCurrentBranch ignore' >&99 2>&1
                push_opencenter_client ${IPADDRS[$node]}
            fi
        done
        ;;

    "opencenter-agent")
        for node in ${nodes}; do
            if [ "$node" != "$(mangle_name 'opencenter-dashboard')" ]; then
                echo "Updating ${node}"
                echo " - setting git config for ${node} on IP : ${IPADDRS[$node]}"
                ssh ${SSHOPTS} root@${IPADDRS[$node]} 'git config --global receive.denyCurrentBranch ignore' >&99 2>&1
                push_opencenter_agent ${IPADDRS[$node]}
            fi
        done
        ;;

    "opencenter-dashboard")
        for node in ${nodes}; do
            if [ "$node" == "$(mangle_name 'opencenter-dashboard')" ]; then
                echo "Updating ${node}"
                echo " - setting git config for ${node} on IP : ${IPADDRS[$node]}"
                ssh ${SSHOPTS} root@${IPADDRS[$node]} 'git config --global receive.denyCurrentBranch ignore' >&99 2>&1
                push_opencenter_dashboard ${IPADDRS[$node]}
            fi
        done
        ;;

    *)
        echo "Usage: push.sh <Cluster-Prefix> {opencenter-all | opencenter | opencenter-client | opencenter-agent | opencenter-dashboard}"
        exit 1
esac
