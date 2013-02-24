---
title: "Vagrant, Chef and the sudo cookbook"
created_at: 2013-02-24 07:48:27 +0100
kind: article
published: false
---

Vagrant is great. Chef is great. Let's say you're using Vagrant to test a Chef config for a server. Maybe you want to add the [Opscode sudo cookbook](http://community.opscode.com/cookbooks/sudo) to manage your sudo package and sudoers? Well, beware!

This particular sudo cookbook replaces the `/etc/sudoers` file to do its thing, wiping out the `%sudo ALL=(ALL:ALL) ALL` line in the process. It just so happens that, on a typical Vagrant box, the `vagrant` user is part of this group, and depends on it to be able to do, well, anything.

Blindly installing the sudo book (as I did) will therefore result in your `vagrant` user being powerless. Side-effects of this include: network failures; an inability to shutdown the VM (`vagrant halt`) and much more!

If you are dead-set on using the sudo cookbook (I gave it up, as it doesn't really do anything useful for a Ubuntu machine anyway), make sure you add the `vagrant` user to the `sysadmin` group, or add the `%sudo ALL=(ALL:ALL) ALL` line back in to the sudoers file.