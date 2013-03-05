#!/usr/bin/env python
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
import requests
import time
import os
import sys
import socket
import urlparse


def get_json(item):
    """nasty hack to get round requests api change"""
    if callable(item):
        return item()
    else:
        return item


def dump_info(endpoint, task_id):
    log_request_url = '%s/tasks/%d/logs' % (endpoint, task_id)
    task_request_url = '%s/tasks/%d' % (endpoint, task_id)

    task_info = requests.get(task_request_url)
    task_json = get_json(task_info.json)

    if (task_info.status_code >= 200 and task_info.status_code < 300):
        task_status = task_json['task']['state']

    log = requests.get(log_request_url + '?watch')
    log_json = get_json(log.json)

    if (log.status_code >= 200 and log.status_code < 300):
        txid = log.json()['request']
    else:
        print 'error getting transaction'
        sys.exit(1)

    urlinfo = urlparse.urlparse(endpoint)

    fd = socket.socket()
    fd.connect((urlinfo.hostname, urlinfo.port))
    fd.send('GET /tasks/%d/logs/%s HTTP/1.0\n\n' % (task_id, txid))

    linedata = []

    while linedata == []:
        data = fd.recv(4096)
        linedata = data.split('\n')

        while(len(linedata) > 0 and
              linedata[0] != '' and
              linedata[0] != '\r'):
            linedata.pop(0)

    sys.stdout.write('\n'.join(linedata))

    while True:
        data = fd.recv(1024)
        if data == '':
            break

        sys.stdout.write(data)

    fd.close()


endpoint = os.environ.get('OPENCENTER_ENDPOINT', 'http://localhost:8080')
if len(sys.argv) < 2:
    print "first argument is task to watch"
    sys.exit(1)

task_id = int(sys.argv[1])

dump_info(endpoint, task_id)
