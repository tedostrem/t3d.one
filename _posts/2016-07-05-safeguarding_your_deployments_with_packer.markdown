---
layout: post
title:  "Safeguarding your deployments with Packer"
date:   2016-07-05
categories: devops 
comments: true
---
For me, one of the greatest challenges of building our solution was making sure we had the ability to deploy on-premise, or on any cloud provider. 

At the root of all the tools we use to make this possible is [Packer](https://www.packer.io/).

>"Packer is an open source tool for creating identical machine images for multiple platforms from a single source configuration." - Hashicorp

By using Packer we know can pack all of our applications and their dependencies into a deployable image, through a single configuration, that can be easily installed on our cloud clusters or on-premise bare metal clusters,

Traditionally when deploying a cluster of machines you often do the provisioning through a configuration management tool like Ansible, Puppet or Chef.

But whether you are provisioning thousands of servers or only a dozen, not only will it take a considerable amount of time but also every step along the way things can fail and very often does, even with idempotent provisioning scripts.

That's because even if it ran correctly last time, maybe links on the internet have changed or an external software package was updated during provisioning and it no longer works. You end up trusting a lot of the internet to be stable which just does not happen in reality.

[How one developer just broke Node, Babel and thousands of projects in 11 lines of JavaScript](http://www.theregister.co.uk/2016/03/23/npm_left_pad_chaos/)

By using Packer to pack your OS and dependencies into one image you have defended against the instability of the outside world without sacrificing reproducibility. Throw packer into your CI/CD pipeline and you can achieve an immutable server configuration and not have to worry about any of your cluster nodes ending up in an inconsistent state. When one gets ill you don't nurse it, you throw it away and get a new one aligning to the [Pets vs Cattle](https://blog.engineyard.com/2014/pets-vs-cattle) analogy.
![Happy sysadmin](/assets/sysadmin.jpg)
*Happy sysadmin*

We have seen in theory how packer can be applied to your production servers, but can the same concept be applied to your development environment?

The short answer is yes, so stay tuned (feel free to sign up for our mailing list), because in the next article we will get you familiar with Packer while setting up a "devbox" for you and your team. It's been a great time saver for me, and I hope it will help you too. 

[Check out a follow-up post on how to build a devbox with Packer, Vagrant and Ansible.](/devops/2016/07/05/safeguarding_your_deployments_with_packer)
