#!/bin/bash

set -e
#set -x

echo INSTALLING AS ${1} against server IP of ${2}

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y build-essential git

nvmVersion=0.8.18

function do_git_update() {
    repo=$1

    if [ -d ${repo} ]; then
        pushd ${repo}
        git checkout master
        git pull origin master
        popd
    else
        git clone git@github.com:rcbops/${repo}
    fi
}

rm -rf .nvm .bower .anvil* .npm

curl https://raw.github.com/creationix/nvm/master/install.sh | sh

. ~/.nvm/nvm.sh
nvm install ${nvmVersion}
nvm alias default ${nvmVersion}

do_git_update ntrapy

pushd ntrapy
cat > config.json <<EOF
{
  "allowedKeys": ["allowedKeys", "timeout", "throttle"],
  "roush_url": "http://${2}:8080",
  "timeout": {
    "short": 2000,
    "long": 30000
  },
  "throttle": 500
}
EOF

make
bash ntrapy
popd
