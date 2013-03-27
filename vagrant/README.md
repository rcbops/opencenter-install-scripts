# Opencenter Vagrant Configuration

This is a very basic vagrant configuration for booting a opencenter cluster. 
Its primary purpose is for offline development.  At the moment it is 
virtualbox specific, but could easily be modified to work with other 
providers.

4 Virtualbox instances are created, one running opencenter server and 
dashboard, three running the agent. All have 1GB of RAM. 

Ports are forwarded to the host via virtualbox, so after running *vagrant up* 
you can access the dashboard at [http://localhost:3000](http://localhost:3000)
and the opencenter endpoint is [http://localhost:8080](http://localhost:8080)

## Usage
Currently vagrant fails to download base images correctly in multi vm
environments, [bug link](https://github.com/mitchellh/vagrant/issues/1467).
As a work around, install the box manually before running vagrant up:

    vagrant box add precise64 http://files.vagrantup.com/precise64.box
    vagrant up

## Other commands
Destroy a cluster

    vagrant destroy [ -f ]

List nodes

    vagrant status

SSH to a node

    vagrant ssh <node name>

More commands

    vagrant --help

## Prerequsites
 * Vagrant installed
 * Virtualbox installed

## Links
 * http://www.vagrantup.com/
 * https://github.com/mitchellh/vagrant
 * https://www.virtualbox.org/
