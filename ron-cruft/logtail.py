#!/usr/bin/env python

import requests
import time
import os
import sys


def dump_info(endpoint, task_id):
    log_request_url = '%s/tasks/%d/logs' % (endpoint, task_id)
    task_request_url = '%s/tasks/%d' % (endpoint, task_id)

    task_info = requests.get(task_request_url)

    if (task_info.status_code >= 200 and task_info.status_code < 300):
        task_status = task_info.json['task']['state']

    log = requests.get(log_request_url)
    log_data = None

    if (log.status_code >= 200 and log.status_code < 300):
        log_data = log.json['log']

    os.system('clear')
    print 'Task %d state: %s\n' % (task_id, task_status)

    if log_data is not None:
        print log_data
    else:
        print 'Error returning log info'
        return False

    if task_status != 'running':
        return False

    return True

endpoint = os.environ.get('ROUSH_ENDPOINT', 'http://localhost:8080')
if len(sys.argv) < 2:
    print "first argument is task to watch"
    sys.exit(1)

task_id = int(sys.argv[1])

while dump_info(endpoint, task_id):
    time.sleep(10)
