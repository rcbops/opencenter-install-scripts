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
CLUSTER_PREFIX=${1:-c1}

items=$($NOVA list |awk "\$4~/^\\s*${CLUSTER_PREFIX}-/{print \$4}" )

for item in ${items}; do
    echo "Deleting ${item}"
    $NOVA delete ${item}
    [ -e /tmp/${item}.log ] && rm /tmp/${item}.log
done
