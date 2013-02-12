#!/usr/bin/env python

import requests
import time
import os
import sys
import socket
import urlparse


def dump_info(endpoint, task_id):
    log_request_url = '%s/tasks/%d/logs' % (endpoint, task_id)
    task_request_url = '%s/tasks/%d' % (endpoint, task_id)

    task_info = requests.get(task_request_url)

    if (task_info.status_code >= 200 and task_info.status_code < 300):
        task_status = task_info.json['task']['state']

    log = requests.get(log_request_url + '?watch')

    if (log.status_code >= 200 and log.status_code < 300):
        txid = log.json['request']
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

        while(len(linedata) > 0 and \
                  linedata[0] != '' and \
                  linedata[0] != '\r'):
            linedata.pop(0)

    sys.stdout.write('\n'.join(linedata))

    while True:
        data = fd.recv(1024)
        if data == '':
            break;

        sys.stdout.write(data)

    fd.close()


endpoint = os.environ.get('ROUSH_ENDPOINT', 'http://localhost:8080')
if len(sys.argv) < 2:
    print "first argument is task to watch"
    sys.exit(1)

task_id = int(sys.argv[1])

dump_info(endpoint, task_id)
