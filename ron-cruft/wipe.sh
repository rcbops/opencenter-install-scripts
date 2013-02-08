#!/usr/bin/env bash

set -e

CLUSTER_PREFIX="c1"

if [ "x$1" != "x" ]; then
    CLUSTER_PREFIX=$1
fi

items=$(nova list | cut -d'|' -f3 | grep "^ ${CLUSTER_PREFIX}-" )

for item in ${items}; do
    echo "Deleting ${item}"
    nova delete ${item}
    rm /tmp/${item}.log
done
