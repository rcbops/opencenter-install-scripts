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
#
set -e

function delete_items {
    for item in ${items}; do
        echo "Deleting ${item}"
        $NOVA delete ${item}
        [ -e /tmp/${item}.log ] && rm /tmp/${item}.log
    done
}

function delete_network {
    if ( $NOVA network-list | grep -q -i ${CLUSTER_PREFIX} ); then
        network_id=$($NOVA network-list | grep -i ${CLUSTER_PREFIX}-net | awk '{print $2}')
        echo "Deleting ${CLUSTER_PREFIX}-net Network $network_id"
        while !( $NOVA network-delete $network_id > /dev/null 2>&1 ); do
            sleep 3
        done
    fi
}

function usage() {

cat <<EOF
usage: $0 options

This script will delete an OpenCenter Cluster.

OPTIONS:
  -h --help  Show this message
  -v --verbose  Verbose output
  -V --version  Output the version of this script

ARGUMENTS:
  -p --prefix=<Cluster Prefix>
        Specify the name prefix for the cluster - default "c1"
  -s --suffix=<Cluster Suffix>
        Specify a cluster suffix - defaults ".opencentre.com"
        Specifying "None" will use short name, e.g. just <Prefix>-opencenter-sever
EOF
}

function display_version() {
cat <<EOF
$0 (version: $VERSION)
EOF
}


####################
# Global Variables #
NOVA=${NOVA:-nova}
CLUSTER_PREFIX="c1"
CLUSTER_SUFFIX=".opencentre.com"
VERSION=1.0.0
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
            if [ "$value" != "--prefix" ] && [ "$value" != "-p" ]; then
                CLUSTER_SUFFIX=$value
                first_char=${CLUSTER_SUFFIX: 0:1}
                if [ $first_char != . ] && [ $CLUSTER_SUFFIX != "None" ]; then
                    echo "$CLUSTER_SUFFIX - adding ."
                    CLUSTER_SUFFIX=."$CLUSTER_SUFFIX"
                elif [ $CLUSTER_SUFFIX = "None" ]; then
                    CLUSTER_SUFFIX=""
                    echo "$CLUSTER_SUFFIX"
                fi
            fi
            ;;
        "--help" | "-h")
            usage
            exit 0
            ;;
        "--verbose" | "-v")
            VERBOSE=1
            set -x
            ;;
        "--version" | "-V")
            display_version
            exit 0
            ;;
        *)
            echo "Using $value as prefix, in future use -p=<prefix>"
            echo "See ./utils/wipe.sh -h for help"
            CLUSTER_PREFIX=$value
            ;;
    esac
done

items=$($NOVA list | egrep -i "${CLUSTER_PREFIX}-opencenter-(client|server|dashboard)[0-9]*${CLUSTER_SUFFIX} " | awk '{print $4}' )

if [[ ${#items[@]} -eq 0 ]]; then
    echo "No servers with prefix $CLUSTER_PREFIX and suffix $CLUSTER_SUFFIX exist, exiting"
    exit 1
fi
delete_items
delete_network
