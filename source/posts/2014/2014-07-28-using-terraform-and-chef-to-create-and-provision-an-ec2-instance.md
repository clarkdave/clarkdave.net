---
title: "Using Terraform & Chef to create and provision an EC2 instance"
slug: using-terraform-and-chef-to-create-and-provision-an-ec2-instance
date: 2014-07-28 23:29:09 +0100
kind: article
published: false
---

[Terraform](http://www.terraform.io/) is an interesting new tool from Hashicorp (Vagrant, Packer) which is designed to help build and launch parts of a server infrastructure.

After reading the docs and checking out the examples, I realised this tool could fit in very nicely indeed with a typical EC2 and Chef workflow. In fact, that's doing the tool a bit of a disservice. It can really be used to configure your entire AWS architecture (your VPCs, security groups, etc) but in this article I'm just going to discuss adding it to to an existing setup.

For example, let's say you have a typical multi-tier server architecture, with a few load-balanced web and app servers. Every now and then you may need to launch a new app/web server, to accomodate growth or just to take advantage of new generation instance types.

My current method of doing this is to have a wiki with a bunch of info in to assist in launching and bootstrapping an instance. For example:

    vpc subnets:
      - subnet-8805cf0 (public, eu-west-1a)
      - subnet-62cf910 (private, eu-west-1c)

    ubuntu AMIs:
      - 12.04 x64 (ebs, para-v): ami-ce7b6fba

    security group ids:
      - internal ssh: sg-12ca7db

    bootstrap a web server:
      $ knife bootstrap <ip> --run-list 'role[base],role[web_server]' ...

So everytime I want to launch a new server, I grab the wiki and use the info to boot the instance and provision it, with a combination of `knife ec2` and the AWS console and `knife bootstrap`.

This works, but with Terraform I can throw this wiki page away, and instead have a nice versioned git repository with some scripts which will configure, launch and then provision every server I need.

<!-- more -->

### Install Terraform

If you haven't already, let's install Terraform now, which you can [download here](http://www.terraform.io/downloads.html). On a mac, you can simply extract it and then move the compiled executables to `/usr/local/bin/` (or somewhere else on your path). Instructions for other platforms are in [the Terraform docs](http://www.terraform.io/intro/getting-started/install.html).

Check it's working by typing `terraform --version` at a prompt.

    $ terraform --version
    Terraform v0.1.0

### Create a Terraform configuration file

These can really live anywhere, but it seems to me that keeping them inside your main Chef repository makes sense