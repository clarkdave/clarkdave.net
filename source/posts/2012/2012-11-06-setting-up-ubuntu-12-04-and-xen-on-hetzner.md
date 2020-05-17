---
title: "Setting up Ubuntu 12.04 and Xen on Hetzner"
slug: setting-up-ubuntu-12-04-and-xen-on-hetzner
description: How to set up a Ubuntu 12.04 (Precise) host and guests using Xen on a Hetzner dedicated server
date: 2012-11-06 20:31:54 +0100
kind: article
published: true
---

[Hetzner](https://www.hetzner.de/en) is a German server provider and has some great prices for leasing a dedicated server. For example, you can grab the [EX 4S](https://www.hetzner.de/en/hosting/produkte_rootserver/ex4) with a Core i7 and 32GB of memory for 60€ a month.

With this much CPU and memory available it makes sense to turn one of these into your own personal VPS provider. This is easy to do and shouldn't take you too long. I'll show you how to replicate my setup, which is a Ubuntu 12.04 (Precise Pangolin) host and guests, where each guest has a static IP and is externally accessible.

This guide doesn't need any prior Xen knowledge but familiarity with Linux, ssh and the terminal is assumed.

<!-- more -->

### Acquire more IP addresses

Because our guests will be externally accessible, we'll need to acquire an IP address for each one. By default, Hetzner servers are given only one IP address but you can buy up to three more for 1 euro each per month.

Head over to the [Hetzner robot](https://robot.your-server.de/), log in, and select your server ('Main functions > Servers' in the menu). Activate the 'IPs' tab and at the bottom you'll see a link 'Ordering of additional IP, failover IP or subnet'.

If you're only planning on having up to three external guests on this machine, the cheapest thing to do is order a single additional IP. Otherwise you could order either a /29 subnet (6 IPs) or /28 subnet (14 IPs), as explained on the [Hetzner wiki](https://wiki.hetzner.de/index.php/IP-Adressen/en).

Under 'purpose of use' I just wrote virtual machine. Once you submit your order you'll have to wait for Hetzner to manually process it, which can take a day or two, but you should eventually get an email with your new IP address enclosed.

### Set up the host

While you're waiting for those IPs, you can start configuring the host. If you already have an operating system installed, you can still use the instructions below but they might not match up exactly (especially if it's not Debian or Ubuntu). If it's a fresh machine however, you may want to just install Ubuntu 12.04 and start from there.

The easiest way to install Ubuntu is, again, through the [Hetzner robot](https://robot.your-server.de/). Select your server and go to the 'Linux' tab. From here you can opt to install Ubuntu 12.04 (which is an LTS release, so a reasonable choice). You'll want to select a 64 bit architecture. And, as the page says, be aware that if you do this it'll clobber anything that you already have on the server.

#### Installing Xen

I'm gonna assume that you've done that and are now staring at a fresh Ubuntu 12.04 ssh session as the root user.

Let's start by installing Xen and xen-tools:

    # apt-get install xen-hypervisor-amd64

Now edit `/etc/default/grub` so the `GRUB_DEFAULT` line looks like this, so we'll boot Xen:

    GRUB_DEFAULT="Xen 4.1-amd64"

And edit `/etc/default/xen` to contain this line:

    TOOLSTACK="xm"

Now run update-grub and reboot:

    # update-grub
    # reboot

When you're back, check that Xen has now loaded:

    # xm list
    Name                                        ID   Mem VCPUs      State   Time(s)
    Domain-0                                     0 31007     8     r-----   11.7

#### Configuring the host's network

Before we can create a new VM there's a few more things we need to do. First, we'll want to configure Xen, and our host, to use static IPs. With a Hetzner server, the host machine acts as a gateway for the guests and forwards them traffic.

Open up `/etc/sysctl.conf` and update it so it has the following settings:

    net.ipv4.ip_forward=1
    net.ipv4.conf.all.rp_filter=1
    net.ipv4.conf.default.proxy_arp=1
    net.ipv4.icmp_echo_ignore_broadcasts=1
    net.ipv6.conf.all.forwarding = 1

Now open `/etc/xen/xend-config.sxp` and ensure that these lines are _commented out_:

    (network-script network-bridge)
    (vif-script vif-bridge)

and also ensure that these lines are present and are _not_ commented out:

    (network-script network-route)
    (vif-script     vif-route)

This will let Xen know we're routing, not bridging, network traffic. Now open up `/etc/network/interfaces` and comment out the `up route add` line, e.g:

    #up route add -net 5.9.119.52 netmask 255.255.255.224 gw 5.9.119.51 eth0

#### Configuring Xen

With all that out the way, the last thing to do is the default Xen settings for new guests. This is done in the file `/etc/xen-tools/xen-tools.conf`. You can replace this file with my config below or copy them into the config by hand. Either way, read my comments and adjust the values (especially the IP addresses).

    # virtual disks will live here
    dir = /home/xen

    install-method = debootstrap

    # these are the default settings for guests which you'll probably
    # override when you actually create it
    size    = 20Gb
    memory  = 512Mb
    swap    = 512Mb
    fs      = ext3

    # this sets all guests up to use Ubuntu 12.04
    dist    = precise
    image   = sparse

    # the gateway IP here MUST be the IP address of your host machine,
    # and the netmask and broadcast addresses should match the output
    # for eth0 when you run `ifconfig`
    gateway   = 5.9.119.30
    netmask   = 255.255.255.224
    broadcast = 5.9.119.50

    # prompt for a root password when creating a guest
    passwd = 1

    kernel = /boot/vmlinuz-`uname -r`
    initrd = /boot/initrd.img-`uname -r`
    arch = amd64

    # german mirror to download ubuntu, as this server is in germany
    mirror = https://de.archive.ubuntu.com/ubuntu

    ext3_options     = noatime,nodiratime,errors=remount-ro
    ext2_options     = noatime,nodiratime,errors=remount-ro
    xfs_options      = defaults
    reiserfs_options = defaults
    btrfs_options    = defaults

    # auto boot new guests
    boot = 1

    serial_device = hvc0
    disk_device = xvda

Make sure the directory you used for `dir` exists and create it if not:

    # mkdir /home/xen

Finally, we need to copy the debian Xen recipe for Ubuntu Precise (thanks to Linus Gasser for pointing this out):

    # cd /usr/lib/xen-tools
    # ln -s debian.d precise.d

And now reboot once more and then it's time to create a guest.

### Create a guest

We'll use the `xen-create-image` command to create a new guest. To create a basic image, which will use the default settings specified in your `xen-tools.conf`, do this, where `<additional ip>` is an extra IP address you acquired from Hetzner:

    # xen-create-image --hostname=guest1.example.com --ip=<additional ip>

But it's also easy to create more customised image with additional arguments:

    # xen-create-image --hostname=guest1.example.com --ip=<additional ip>
      --vcpus=2 --memory=4Gb --swap=1Gb --size=50Gb

This will create an image with 2 CPUs, 4GB of memory, 1GB swap and a 50GB hard disk.

If you didn't set `boot = 1` in your xen conf, you can start this image now using this command:

    # xm create /etc/xen/guest1.example.com.cfg

To confirm the VM has booted, run `xm list`:

    xm list
    Name                                        ID   Mem VCPUs      State   Time(s)
    Domain-0                                     0 31007     8     r-----   3624.8
    guest1.example.com                           2  4096     2     -b----    13.4

If everything has worked, you should now be able to ssh into this machine using the ip and root password you were prompted for during creation.

    # ssh root@<guest ip>

If this doesn't work, then there's a problem with the network configuration. You can still access the guest without network connectivity to help diagnose the problem:

    # xm console guest1.example.com

If this does happen, double check all of your addresses -- the guest must have the host as its gateway, and the subnet must match up on both.

#### Editing a machine

To edit a machine (change its memory or vcpus) first shut it down safely:

    # xm shutdown guest1.example.com

Then open up the file `/etc/xen/guest1.example.com.cfg` and edit the properties:

    vcpus   = '2'
    memory  = '1024'

and start it up again:

    # xm create /etc/xen/guest1.example.com.cfg

### All done!

Hopefully that should be it. You'll be able to access your new guest machine internally and externally, and can create as many as you have spare IP addresses.

Thanks for reading! I'm certainly not a Xen master, so if you see something here that can be improved please let me know and I'll update the guide.
