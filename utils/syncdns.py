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
"""
Update a DNS domain to match a opencenter development cluster.
This is specifically for use with opencenter-cluster.sh, the same prefix used
in that script should also be passed to this script.

The DNS entries are named after the role of each node and do not include the
prefix. This ensures that endpoints can stay consistent while creating various
developement clusters.

Example usage:

utils/syncdns.py uk.rs.wherenow.org dev2
uk.rs.wherenow.org
  opencenter-dashboard.uk.rs.wherenow.org A 95.138.172.27
  opencenter-client2.uk.rs.wherenow.org A 95.138.172.143
  opencenter-client1.uk.rs.wherenow.org A 95.138.170.92
  opencenter-server.uk.rs.wherenow.org A 95.138.170.23
"""

import sys
import os
import argparse
import re
import pyrax

class Quit(SystemExit):
    pass


class DNSManager(object):

    def __init__(self, domain, ttl=300):
        self.dns = pyrax.cloud_dns
        self.ttl = ttl
        domains = self.dns.list()
        domain_names = [d.name for d in domains]

        if domain not in domain_names:
            raise Quit("Domain %s not in cloud dns domains (%s)" % (
                self.args.domain, ",".join(domain_names)
            ))

        self.domain = [d for d in domains if d.name == domain][0]

    def add(self, name, data, record_type='A'):
        print "adding %s --> %s" % (name, data)
        self.domain.add_records([{
            'type': record_type,
            'name': '%s.%s' % (name,
                               self.domain.name),
            'data': data,
            'ttl': self.ttl
        }])

    def __str__(self):
        records = []
        for domain in self.dns.list():
            print domain.name
            for record in domain.list_records():
                if record.type != 'NS':
                    records.append("  %s %s %s" % (record.name,
                                                   record.type,
                                                   record.data))
        return "\n".join(records)

    def ensure_a_record(self, name, ip):
        fqdn = '%s.%s' % (name, self.domain.name)
        for record in self.domain.list_records():
            if fqdn == record.name:
                record.update(data=ip)
                return

        #record not found, add
        self.add(name, ip)


class OpencenterCluster(object):
    def __init__(self, prefix_addition, prefix, dnsmanager, cloudservers):
        self.prefix = prefix
        self.prefix_addition = prefix_addition
        self.cs = cloudservers
        self.dnsmanager = dnsmanager
        self.cluster_re = re.compile(r'^%s%s-(?P<role>.*)' %
                                     (self.prefix, self.prefix_addition))


    def get_instances(self):
        """returns an itterable of tuples (server_name,server_ip)"""
        for server in self.cs.servers.list():
            match = self.cluster_re.match(server.name)
            if match:
                for ip in server.networks['public']:
                    if ip.count('.'):
                        v4ip = ip
                yield (match.group('role'), v4ip)

    def sync_dns(self,):
        """Create/update dns records based on existing instances.
        Only reads metadata from instances that match the cluster_re
        """

        for server_name, server_ip in self.get_instances():
                self.dnsmanager.ensure_a_record(server_name, server_ip)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('domain',
                        help="DNS domain registered with cloud DNS")
    parser.add_argument('--pyrax_cfg',
                        help="Path to pyrax credentials file"
                             " - https://github.com/rackspace/pyrax",
                        default=os.path.expanduser("~/.pyrax.cfg"))
    parser.add_argument('prefix',
                        help="opencenter-cluster prefix")

    args = parser.parse_args(sys.argv[1:])

    try:
        pyrax.set_credential_file(args.pyrax_cfg)
        cs = pyrax.cloudservers
        dnsmanager = DNSManager(args.domain)
    except (pyrax.exceptions.FileNotFound,
            pyrax.exceptions.InvalidCredentialFile), e:
        raise Quit("Failed to authenticate: %s" % e)

    #syncdns print and quit if the syncdns option was specified
    cluster = OpencenterCluster('',
                           args.prefix,
                           dnsmanager,
                           cs)
    cluster.sync_dns()
    print str(dnsmanager)
