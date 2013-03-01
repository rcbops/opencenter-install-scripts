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
NOVA=${NOVA:-nova}
CLUSTER_PREFIX=${1:-c1}
items=$($NOVA list |awk "\$4~/^\\s*${CLUSTER_PREFIX}-/{print \$4}" )

for item in ${items}; do
    echo "Deleting ${item}"
    $NOVA delete ${item}
    [ -e /tmp/${item}.log ] && rm /tmp/${item}.log
done

if ( $NOVA network-list | grep -q ${CLUSTER_PREFIX} ); then
    network_id=$($NOVA network-list | grep ${CLUSTER_PREFIX}-net | awk '{print $2}')
    echo "Deleting ${CLUSTER_PREFIX}-net Network $network_id"
    while !( $NOVA network-delete $network_id > /dev/null 2>&1 ); do
        sleep 3
    done
fi
