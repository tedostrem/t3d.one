---
layout: post
title:  "Building an SDK for Robots"
date:   2017-04-06
categories: development
comments: true
---
*or, Building a platform agnostic cross-compiling toolchain for an ARM based robot.*

In the last couple of months I've had the pleasure of working with a young, and very interesting robotics company here in Beijing. They are called [Vincross](https://www.vincross.com/?utm_source=blog&utm_medium=link&utm_campaign=DevelopRobotSDKBlog), and they are building a robot called [HEXA](https://www.vincross.com/hexa?utm_source=blog&utm_medium=link&utm_campaign=DevelopRobotSDKBlog). 
![HEXA taking on a Lion](/assets/hexa_cat.png)
*HEXA taking on a Lion*


What's interesting about this startup is that they are providing HEXA owners with an SDK which they can use to build their own applications for the HEXA, called *Skills*. 

HEXA owners can then publish their *Skills* to the [Skill Store](https://www.vincross.com/skill-store?utm_source=blog&utm_medium=link&utm_campaign=DevelopRobotSDKBlog), where they can also download other developers *Skills*.


A *Skill* consists of two parts: 
* Remote - A web application running on a mobile device used to control the HEXA remotely. 
* Robot - A Golang application running on the robot, typically where the core *Skill* logic lives. 


When I arrived at Vincross, they had just shipped their first batch of HEXA's to customers together with an SDK and command-line interface for *Skill* development.


*Skill* development workflow worked as such: 
1. User runs `mind init` and a *Skill* project is scaffolded.
2. User writes some Golang code and JavaScript code.
3. User runs `mind run` and code is packaged into a .mpk file which is uploaded to the robot, compiled and then executed.

The reason it had to be compiled on the robot is because the robot is using an ARM processor, while the developer's machine most likely is using an x86 processor.

Golang supports cross compiling to ARM architecture, but abstracting away the build process of Golang applications on all the platforms supported by MIND SDK (Windows, Linux and macOS) is not trivial. Add to that, compilation of C++ libraries like OpenCV, and bindings to these libraries using SWIG/CGO, and it's easy to see why the decision of "let's just compile on the robot instead" makes a lot of sense.

The benefits we would reap from cross-compiling are:
* Ability to build third-party or non-golang libs into *Skills*.
* *Skills* can theoretically be developed in any language.
* Shorter build times.
* *Skills* source code can be proprietary and closed.


As we all know, Apple supports cross compilation of iOS applications to both the simulator running on x86, as well as to the actual phone, which is running on ARM.
However, it's easy to see why it's not possible to develop iOS apps on Windows or Linux. Apple just doesn't want to spend the time porting their own toolchain, dealing with the ins and outs of a 3rd party operating system, and keeping up with breaking changes when they already have their own hardware, operating system and XCode.

So how can we build a cross-compiling toolchain that will support cross compiling to x86 and ARM and at the same time be platform agnostic? 

We do virtualization where it's needed. And who does that? Docker does.
![](/assets/docker.jpg)

As long as we can get the whole cross-compiling toolchain working in Linux, we can ship `mind` as a binary, which responsibilities are very simple:
1. To make sure Docker is installed
2. To download the latest `mindcli` image
3. To forward `mind` subcommands into the `mindcli` docker container.

So as far as platform agnostic goes, we trust that docker will provide us with that abstraction, and we pray that they do not mess up too often.

Alright, lets dig into the implementation details:

## Cross compiling C/C++ 
The first goal was to cross-compile C/C++ applications, more specifically, we wanted to cross-compile OpenCV since it has a lot of features that are useful when you are building a robot that is suppose to visually understand the world.

We decided that, if we manage to cross compile OpenCV and get Go bindings to OpenCV working, our users should be able to do the same for any other library of their choice.

To cross compile C++ for ARM, all you need is the correct gcc cross compiling toolchain for your ARM processor. In our case, the HEXA is equipped with an ARMv7 processor with support for **h**ardware **f**loating point calculations. Thus, we want the arm-linux-gnueabi**hf** version of the cross compiling tools. 
```docker
FROM ubuntu:14.04
ENV CROSS arm-linux-gnueabihf
RUN apt-get update && apt-get upgrade -y && apt-get install -y \
    unzip \
    wget \
    git \
    gcc-${CROSS} \
    g++-${CROSS} \
    cmake \
    pkg-config \
    && apt-get clean && apt-get autoremove --purge
# Setup cross compilers
ENV AS=/usr/bin/${CROSS}-as \
    AR=/usr/bin/${CROSS}-ar \
    CC=/usr/bin/${CROSS}-gcc \
    CPP=/usr/bin/${CROSS}-cpp \
    CXX=/usr/bin/${CROSS}-g++ \
    LD=/usr/bin/${CROSS}-ld
```
We also want to install Go and set it up for cross compilation.
```docker
ENV GOVERSION go1.8
# Install Golang amd64
RUN wget https://storage.googleapis.com/golang/${GOVERSION}.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf ${GOVERSION}.linux-amd64.tar.gz && \
    rm ${GOVERSION}.linux-amd64.tar.gz
# Install Golang armv6l
RUN wget https://storage.googleapis.com/golang/${GOVERSION}.linux-armv6l.tar.gz && \
    tar -xzf ${GOVERSION}.linux-armv6l.tar.gz && \
    cp -R go/pkg/linux_arm /usr/local/go/pkg/ && \
    rm -fr go && rm -frv ${GOVERSION}.linux-armv6l.tar.gz
# Configure Golang
ENV GOPATH=/go \
    GOOS=linux \
    GOARCH=arm \
    GOARM=7 \
    CGO_ENABLED=1
ENV PATH=${PATH}:${GOPATH}/bin:/usr/local/go/bin \
```
*Above is a snippet of the Dockerfile in our ([Open sourced cross compiler image](https://github.com/vincross/mindsdk/tree/master/xcompile). The full version also ensures that future packages installed with `apt-get` will include their respective ARM architecture version of that package, which is required when installing the build dependencies of OpenCV)*

With this Dockerfile in place and built, all we have to do is to `docker run` it with the OpenCV source mounted into the container, install a few dependencies with `apt-get`, and execute `cmake` on the OpenCV provided cmake file as such:
```shell
$ apt-get update && apt-get install -y libavcodec-dev ...
$ cmake -DCMAKE_INSTALL_PREFIX=${OPENCV_ARTIFACTS_DIR} \
	-DCMAKE_TOOLCHAIN_FILE=../arm-gnueabi.toolchain.cmake \
	../../.. && make && make install
```
After a pretty long compile time (Luckily we only have to compile once), the `${OPENCV_ARTIFACTS_DIR}` now contains all of OpenCV's dynamic libraries and header files.


## Golang bindings 
To generate Golang bindings for C libraries, one would typically use CGO, and when binding for C++ libraries, one would use SWIG.
Writing the Golang bindings can be a pretty mundane process, and in our case we were lucky. Some cool people had already gone through the effort of writing [Golang bindings for OpenCV using SWIG.](https://github.com/lazywei/go-opencv) 

Now, to cross compile our Golang application using the Golang bindings to OpenCV, all we need to do is to `docker run` our container with our source mounted, tell Go how to find its dependencies...

```shell
export PKG_CONFIG_PATH="${OPENCV_ARTIFACTS_DIR}/lib/pkgconfig"
export CGO_CFLAGS="-I${OPENCV_ARTIFACTS_DIR}/include"
export CGO_LDFLAGS="-L${OPENCV_ARTIFACTS_DIR}/lib"
```
...and then compile our application as usual.
```shell
$ go build -o opencvexample opencvexample.go
```

## Running it  on the HEXA.
If OpenCV was compiled as a static library, we would just have to upload the binary to the HEXA, execute it and be done with it. 

However, since we are linking against a C++ library, we now don't have a statically linked executable anymore, and it will to try to find the shared libraries it's depending on.

*(We could build OpenCV against musl-libc instead, but since HEXA is running ubuntu 14.04, we already have glibc anyway)*

But its an easy problem to solve.
1. Pack the binary and the `${OPENCV_ARTIFACTS_DIR}/lib` into a zip file. 
2. Upload the zip file to the robot and unzip it.
3. On the robot, tell the run time shared library loader to look for libraries in our `lib/` directory and execute the application.
```shell
LD_LIBRARY_PATH=`pwd`/lib ./opencvexample
```

**Done !**
We can now cross compile C/C++/Golang applications on our PC, and pack it together for upload and execution on the robot.

**However**, we for sure don't want our dear users to have to go through this whole process, so we need to provide them with some **sweet abstractions**:
![](/assets/mindcli.png)

*Through the MIND Command-line interface, users have everything they need to develop *Skills* for the HEXA.* 

## MIND Software Development Kit 

Let's start by showing a very basic example of a *Skill*. All it does is make the HEXA stand up.
```golang
package StandUpSkill

import (
  "mind/core/framework/drivers/hexabody"
  "mind/core/framework/skill"
)

type StandUpSkill struct {
  skill.Base
}

func NewSkill() skill.Interface {
  return &StandUpSkill{}
}

func (d *StandUpSkill) OnStart() {
  hexabody.Start()
  hexabody.Stand()
}

func (d *StandUpSkill) OnClose() {
  hexabody.Close()
}
```
As seen above, we are importing `skill` and the `hexabody` driver which we use to make the HEXA stand up using its 6 legs. These two packages are part of the **MIND Binary Only Distribution Package**, which previously came prebaked on the HEXA.

Since we now are compiling inside of a docker container instead of on the HEXA, we don't need to ship the package prebaked on the HEXA. Instead, we just put it inside of our `GOPATH` on the cross-compiling capable container.

### Let's delete some code
All of the things that the previous CLI used to do, like entrypoint generation, packaging, uploading, installation, execution, log retrieval, communication with HEXA over websockets etc, can now be accomplished with Linux tools and **shell scripts instead of thousands of lines of Golang code**.

The key to this functionality is this Golang function. 
```golang
func (mindcli *MindCli) execDocker(args []string) {
  cmd := exec.Command("docker", args...)
  cmd.Stdout = os.Stdout
  cmd.Stderr = os.Stderr
  cmd.Stdin = os.Stdin
  err := cmd.Run()
  if err != nil {
    fmt.Println(err)
  }
}
```


We can implement `mind build` by doing a `docker run` on the container with the current folder mounted, injecting some environment variables and execute the following shell script inside the container.
```shell
#!/usr/bin/env bash
set -eu
export PKG_CONFIG_PATH="/go/src/skill/robot/deps/lib/pkgconfig"
export CGO_CFLAGS="-I/go/src/skill/robot/deps/include"
export CGO_LDFLAGS="-L/go/src/skill/robot/deps/lib"
mindcli-genmain
go build -o robot/skill skillexec
```

We can pack the *Skill* together as an `.mpk` file using *zip* like this:
```shell
zip -r -qq /tmp/skill.mpk manifest.json remote/ robot/skill robot/deps robot/assets robot/deps
```

And then serve the `.mpk` file to the HEXA using Caddy.
```shell
#!/usr/bin/env bash
set -eu
MPK=$1
cat >/tmp/Caddyfile <<EOL
0.0.0.0:${SERVE_MPK_PORT}
root .
rewrite / {
        regexp .*
        to /${MPK}
}
EOL
caddy -quiet -conf="/tmp/Caddyfile"
```
In addition, all of the websocket logic was rewritten and simplified using [The WebSocket Transfer Agent](https://github.com/esphen/wsta) 
```shell
$ echo "hello hexa" | wsta ws://my.hexa
```

As I mentioned earlier, the only thing the MIND CLI has to do is forward subcommands into the docker container. The only exception is scanning the local network for HEXAs.

*When scanning the network for HEXAs, the CLI will send UDP packets to the networks multicast address and wait for a UDP packet to be sent back by the HEXA containing its name and serial number. When doing this we can not NAT to the docker container since it would cause us to lose the packet source address. (Maybe we will run the container on host network in the future)*

### Wrapping it all up

The MIND SDK consists of the following parts:
* XCompile Docker Image - An image preconfigured for cross compilation of C/C++ and Golang code to ARM architecture.
* MIND Binary Only Distribution - Used by the *Skill* to interface with the HEXA hardware.
* MIND JavaScript SDK - Used by the remote part of the *Skill* to talk to the the HEXA.
* Templates and shell scripts used to generate the *Skill* main entrypoint.
* Makefiles and shell scripts used to compile and pack a *Skill* with its 3rd party dependencies and assets into an *mpk* file. 
* Scripts to upload, install and execute *Skills* on the HEXA.
* Scripts to retrieve logs and communicate with the HEXA in realtime using websockets.

All of the parts listed above go through different build pipelines, to finally be packaged into a single docker image published on [docker hub](https://hub.docker.com/r/vincross/mindcli/)

In front of this docker image stands the [MIND Command-line Interface](https://www.vincross.com/developer/introduction/getting-started/macos-&-linux?utm_source=blog&utm_medium=link&utm_campaign=DevelopRobotSDKBlog) abstracting away all of the docker commands. 

Since Docker is providing the host operating system abstraction layer, we had, after getting it to run on macOS and Linux, close to 0 issues getting the whole toolchain working in Windows, both with and without Hyper-V.

Here is an example showing how a user would go about developing a new *Skill* for the HEXA using the SDK.
```shell
$ mind scan
10.0.0.76 Susan 
10.0.0.21 Catherine 
10.0.0.51 Andy
$ mind set-default-robot Andy
$ mind init HelloWorldSkill
$ cd HelloWorldSkill
$ vim robot/src/HelloWorldSkill.go
...
# do some coding
...
$ mind build && mind pack && mind run
Installation started
Uploading 0%
Uploading 21%
Uploading 42%
Uploading 65%
Installing 80%
Installation successful !
Point your browser to: http://localhost:7597
Connecting
Connected !
Battery: 100% [Charging]
```
To use OpenCV inside a *Skill*, we can create a simple Makefile or shellscript for building OpenCV:
```shell
apt-get update && apt-get install -y libavcodec-dev ...
cmake -DCMAKE_INSTALL_PREFIX=${OPENCV_ARTIFACTS_DIR} \
	-DCMAKE_TOOLCHAIN_FILE=../arm-gnueabi.toolchain.cmake \
	../../.. && make && make install
```
and build OpenCV inside the cross compiling container by executing `mind x make`, followed by copying the generated libraries and headers into the `robot/deps` folder before building the *Skill*. 
```shell
$ cd OpenCV
$ mind x make
$ cd ..
$ cp -R OpenCV/artifacts/lib OpenCV/artifacts/include robot/deps/ 
$ mind build 
```

And lastly, by executing a `mind upgrade`, the latest version of the MIND SDK container will pulled down from docker hub.


### It's open source ! 
We opensourced the whole [MIND Software Development Kit on GitHub](https://github.com/vincross/mindsdk) and hope that it will be useful to HEXA owners as well as other robotics developers.

If you have any comments or suggestions please feel free to post them in the comment section below.

See you next time!
