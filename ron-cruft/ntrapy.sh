#!/bin/bash

set -e
set -x

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

curl https://raw.github.com/creationix/nvm/master/install.sh | sh

pushd .nvm
source nvm.sh
nvm install ${nvmVersion}
nvm alias default ${nvmVersion}
popd

do_git_update ntrapy

pushd ntrapy
cat > config.js <<EOF
var config = {};

config.roush_url = "http://${2}:8080";
config.db = "ntrapy";
config.db_dir = ".";
config.secret = "???";
config.timeout = {short: 2000, long: 30000};
config.interval = 5000;

module.exports = config;
EOF
export PATH=$PATH:/root/.nvm/v${nvmVersion}/bin

make
bash ntrapy
popd
