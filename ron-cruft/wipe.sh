#!/usr/bin/env bash

set -e
NOVA=${NOVA:-nova}
CLUSTER_PREFIX=${1:-c1}

items=$($NOVA list |awk "\$4~/^\\s*${CLUSTER_PREFIX}-/{print \$4}" )

for item in ${items}; do
    echo "Deleting ${item}"
    $NOVA delete ${item}
    [ -e /tmp/${item}.log ] && rm /tmp/${item}.log
done
