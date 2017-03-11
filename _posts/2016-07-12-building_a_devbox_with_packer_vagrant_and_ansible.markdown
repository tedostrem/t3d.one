---
layout: post
title:  "Building a Devbox with Packer, Vagrant and Ansible"
date:   2016-07-12
categories: devops 
---

In the previous article [Safeguarding your deployments with packer](/devops/2016/07/05/safeguarding_your_deployments_with_packer) we explained in theory how we can use Packer to achieve immutable server configurations.

At Traintracks, we not only use Packer for server deployments but also for our development environment.

There are many benefits to this such as:

* Every engineer's development environment is the same.
* New engineers can start being productive from day one.
* What works on my machine will work on any other engineers machine.
* What works on my machine will (probably) work in production.
* Development environment is host operating system agnostic (Even works for windows users).

When using Packer for server deployments you want to keep all of your server configurations as immutable as possible. However, for a development environment, it's just not practical to throw away your devbox and build a new one every time something in the dev environment has been updated.

Instead of only optimising for immutability and consistency we also need to optimise for efficiency (developer hours cost more than computer hours).

This is why we are gonna bring in two new concepts here:

* Static dependencies (Dependencies that do not get updated very often, eg. operating system, system packages, third party software like docker, ansible, git, curl etc).
* Dynamic dependencies (In-house tooling and configuration files that are constantly iterated on)

We are going to use Packer to pack all of our static dependencies and Ansible to provision our dynamic dependencies inside of Vagrant.

A simple example to clarify what I mean:

At Traintracks we have a remote working culture but most of our engineers are in Beijing.

That means that everything that requires free and fast access to the greater internet goes into our static dependencies (Packer). Third party installation scripts might be pulling from Amazon S3 (blocked in China).

Kubernetes is downloaded from google servers, which means it is also blocked.

Due to internet connectivity and speed limitations we want these types of dependencies to be downloaded and configured once and then distributed to all the team members without anyone having to jump on a VPN to download software dependencies.

Of course we could host these dependencies on our own servers and we very often do but for dependencies that are not being changed a lot (our static dependencies) we prefer to grab them directly from the correct source once, and distribute everywhere just like we do for our production servers.

So, enough talking and let's get to it!

**Prerequisites**

* Packer 0.10 or above
* Vagrant 1.8.1 or above.
* Ansible 2.0 or above.

Assuming you're on a mac and use [homebrew](http://brew.sh):
```shell
$ brew cask install virtualbox
$ brew cask install vagrant
$ brew install packer
$ brew install ansible
``` 

**Packer (Static dependencies)**

We have prepared a boilerplate for a Packer configuration that is very similar to the one we use at Traintracks that we will use as our base.

This boilerplate will give you a box containing:

* Ubuntu 16.04
* VirtualBox Guest Additions
* Docker, kubectl and kargo
* git, wget, curl, vim, zsh, htop, tmux, ntp

```shell
$ git clone git@github.com:traintracks/devbox.git
$ cd devbox
```
Lets start by inspecting the packer folder
```shell
packer
├── ansible
│   └── playbook.yml
├── devbox.json
├── files
│   └── motd
├── http
│   └── preseed.cfg
└── scripts
    ├── ansible.sh
    ├── cleanup.sh
    ├── install.sh
    └── setup.sh
```
**devbox.json** is the file that explains to packer how to build the devbox, which files to copy and which scripts to run.
You can also add provisioners for other image types (ec2, vmware etc) in here.
If you want to use another base operating system you define that
in here and provide an url and hash sum to the base image.

**preseed.cfg** will be fetched by the Ubuntu installer from a local web server that Packer has spun-up that will automate the Ubuntu installation by automatically providing answers to all of the installation prompts.

**scripts folder** contains scripts that makes little sense to perform with ansible. Eg: ansible.sh installs ansible and cleanup.sh does final cleanup before exporting the box.

**playbook.yml** is the ansible playbook where you define packages to be installed and other configurations.

To customise the devbox to your needs you will mainly be interested in devbox.json and playbook.yml.

Now we can go ahead and build the devbox with packer.
```shell
$ cd packer
$ packer build devbox.json
```
*To see the installation progress you can either go from the VirtualBox UI, watch the preview screen, select Show from Machine menu, or set headless to false in the devbox.json file.*

**Dynamic dependencies**

As mentioned earlier your team might have tooling or configuration that is frequently updated which you want to propagate throughout your team more often than you want to build a new box with Packer.

One example could be a company wide ssh config or a common zshrc file.
The boilerplate contains a simple example on how this is done.

Lets have a look inside of the Vagrantfile.
```shell
$ cd ..
$ cat Vagrantfile
```

Check out the lines between  ```# PROVISION START``` and ```# PROVISION END```

The first three lines copies your host machines default ssh keys into the devbox so that you can access your remote machines from the devbox as you would from your host machine.
We also copy your git config so that you can make git commits from within the devbox.

After that you can see that we are calling ansible to do the rest of the provisioning using the ansible/playbook.yml file.

```yaml
  ---
  - hosts: all
    tasks:
    - name: Copy zshrc
      copy: src=files/zshrc dest=/home/vagrant/.zshrc
    - name: Set shell to zsh
      become: yes
      user: name=vagrant shell=/bin/zsh
```
Currently all it does is setting the default shell to zsh and copies a zshrc file into the vagrant home folder but it serves as a template for you to add all of the other tools and configurations that go into the devbox.

For example you can add a company wide ssh config that is pushed to git and all your team mates have to do to get the new config is a ```git pull``` followed by a ```vagrant provision```.

Once you notice a dynamic dependency is being updated less frequently you can move it to the static dependencies instead (A mere copy paste between two ansible files).

Now lets add the box to vagrant, provision it and start it up!
```shell
$ cd ..
$ vagrant box add devbox packer/builds/devbox.box
$ vagrant up
```

If everything went well you should be greeted with a shell looking like this.

![](/assets/devbox.png)
