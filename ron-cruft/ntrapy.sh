#!/bin/bash
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
