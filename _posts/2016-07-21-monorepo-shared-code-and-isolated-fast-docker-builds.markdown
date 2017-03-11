---
layout: post
title:  "Monorepo, Shared Code and Isolated Fast Docker Builds"
date:   2016-07-21
categories: devops 
---
Docker does not make it easy for those who want to do isolated builds of separate applications using shared code in a monorepo.

There are probably many ways to solve it, but for me, finding a way that works in a consistent way for all of the projects and languages in our code base was not trivial.
Here I'm going to present a solution that works for us at Traintracks.

This solution is agnostic to language, package manager, build system, project hierarchy and can be implemented in the same way throughout your whole stack. (Please do comment if you notice a case where it's not)

So here it goes!

##### Cached dependencies
If you've ever used Scala and SBT, you probably know that you'll have enough time to grow and cut your toenails (might even start eating them) in between builds if your build cache gets reset at each build.

The immutable nature of docker plus the fact that SBT does not have have a `package.json` or a `requirements.txt` file like `npm`/`pip` means that we can't cache our dependencies easily.

Every time we update some code we are back to 0 because the downloading of dependencies and building of code happens in the same step.

**Build containers to the rescue?**

It goes pretty much like this. 

1. You create a container with all the tools to build your application. 
2. You run the container and tell it to build your application with your project folder mounted into a folder in the container.
3. You execute your build inside of the container and everything is persisted on your host for your next build.

All good? not really, unless you also mounted your ~/.m2 or ~/.ivy2 folder or redirected them to somewhere else and also don't mind keeping the same build artifacts shared between your host and docker container. 

Adding to that, if you are in Vagrant and share your workspace volume with your host and have not set up NFS then be prepared for really slow build times.

Besides, you still want to have your [static dependencies cached away and separate from your dynamic dependencies](http://blog.traintracks.io/building-a-devbox-with-packer-vagrant-and-ansible-2/) so that your team's code can be built by all engineers regardless of how broken the internet is at that point. This is particularly relevant if you are behind a corporate firewall or in someplace with internet connectivity issues.

That means that your build container needs to already come shipped with the third party dependencies required before we execute the build in it.

To summarize, we need to do an initial build of the application inside the container before it can act as a pre-cached build container. As dependencies update the build container will be rebuilt.

Let's continue to the next requirement.

##### Shared code
Maybe you made a nice library with some transformations that you want to use both in your data ingestion app and in your query application.
On top of that, maybe one of the engineers on your team enjoys sitting in IntelliJ with all the Scala projects open in the same workspace, modifying the shared library code and recompile both of his projects from within the IDE. 

How do we build individual applications isolated when they have shared dependencies above themselves in the project hierarchy?

Lets imagine a monorepo and try to figure out how to build coolapp and awesomeapp that both share the dependencies lib1 and lib2.
We are going to use Golang for this example instead of Scala (for simplicity) but the same concepts apply.
```shell
├── coolapp
│   ├── coolapp.builder.dockerfile
│   ├── ...
├── awesomeapp
│   ├── awesomeapp.builder.dockerfile
│   ├── 
├── lib1
│   └── ...
└── lib2
    └── ...
└── i_am_too_fat_for_your_build_context
    └── ...
```

We can't just execute ```docker build -t coolapp .``` inside of coolapp because lib1 and lib2 are outside of it's context.

However, we can move the context up one directory and specify the dockerfile like this.

```shell
$ docker build -t coolapp -f coolapp/Dockerfile . 
```

We are getting there. but wait, there is a folder that says its too fat for your docker context and we are not even depending on it.

What if we have so many projects in this repo that the size of the build context we send to docker ends up being a huge build time bottleneck?

Typically we would add a .dockerignore file that tells docker which files to ignore when uploading the context but that won't work here since what we want to ignore is conditional (depending on which app we are building).

So what we need to do is to cherry pick our build context and send it to docker (Note that we're using GNU Tar and not BSD Tar).
```shell
$ tar -zcf - ../lib1 ../lib2 | docker build -t coolapp-builder -f coolapp/coolapp.builder.dockerfile
```
*GNU Tar also takes --exclude-from-file where you can pass a .gitignore or a .dockerignore. Note that .gitignore have
expansion rules not supported by Tar so you are either gonna have to tar dependencies individually and concatenated, ask git for the relevant files or align to a unified ignore pattern across your libraries.*

Lets have a look at the Dockerfile in coolapp.
```docker
FROM golang:1.6
RUN apt-get update && apt-get install -y rsync
ADD . /go/src/traintracks/
WORKDIR /go/src/traintracks/coolapp
RUN go get ./...
```

Lets build the container, jump into it and look at the content of our GOPATH.
```shell
$ docker exec -it coolapp-builder bash
$ tree $GOPATH
|-- bin
|   |-- coolapp
|-- pkg
|   |-- linux_amd64
|       |-- github.com
|       |  |-- Sirupsen
|       |       |-- logrus.a
|       |- traintracks
|           |-- lib1.a
|           |-- lib2.a
|-- src
    |-- github.com
    |   |- Sirupsen
    |       -- logrus
    |           |--  ...
        -- traintracks
        |-- coolapp
        |   |-- coolapp.builder.dockerfile
        |   |-- coolapp.dockerfile
        |   |-- coolapp.go
        |-- lib1
        |   -- lib1.go
        --- lib2
            -- lib2.go
```

It has downloaded our dependencies from the internet and also built coolapp-builder with our cherry picked dependencies.

Now we have edited a line of code in lib1 and want to rebuild coolapp.
We are going to execute the container with the build context mounted to /mount and tell it to make an rsync between /mount and the corresponding folder in the GOPATH.

```shell
$ rsync -auiv --filter=\":- .gitignore\" /mount/ /go/src/traintracks/
```
*Remember what I said about .gitignore passed into Tar, the same applies here*

Now we just have to build the app again with a ```go get ./...``` and unless you have new internet dependencies since last build the build will be as fast as your CPU and disk.

Final step is to copy our artifacts to somewhere in the mounted folder.

```shell
$ cp -v /go/bin/coolapp  /mount/coolapp/output/
```

Back on our host we can inspect the folder again
```shell
├── coolapp.builder.dockerfile
├── coolapp.go
└── output
    └── coolapp
```

So there is your coolapp binary ready for you to throw it into a plain linux container without any builds tools or source code.
This will keep your containers lean and will avoid potential leakage of code.

coolapp.dockerfile might look something like this
```docker
FROM ubuntu:14.04
ADD output/* /usr/local/bin
CMD coolapp
```

##### Good ol' Makefiles
That was a lot of steps and it might seem like a very troublesome process but actually we can wrap all of it in this [Makefile](https://github.com/traintracks/docker_monorepo_example/blob/master/src/traintracks/coolapp/Makefile) and work ourselves towards a generalised solution that will work for all  of our projects.

I have created an example repository that you can clone and try out.
```shell
$ git clone git@github.com:traintracks/docker_monorepo_example.git
$ make builder   # Creates the builder container
$ make build     # Builds project using builder container
$ make runner    # Creates the runner container
$ make run       # Runs coolapp
$ make all       # Runs all of the previous steps
$ make           # Runs all targets except builder
```

To summarise what all of this gave us.

* Pre-cached dependencies without a requirements file.
* Separation between build/run containers.
* No dirty artifacts on host.
* Support for a project hierarchy of your choice.
* Fast builds on shared disks in Vagrant.
* A unified build system for all your applications.

If you think you might have a better solution than what I presented here or have some cool improvements please leave me a comment ! I'm more than happy to learn how others have tackled these problems.
