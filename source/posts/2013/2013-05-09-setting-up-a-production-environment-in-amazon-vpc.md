---
title: "Setting up a complete environment in Amazon VPC"
slug: setting-up-a-production-environment-in-amazon-vpc
date: 2013-05-09 12:18:40 +0100
kind: article
published: false
---

Amazon Virtual Private Cloud (VPC) has a lot of great features. You can have your own private and public subnets, with dedicated private IP addresses, set up granular security groups to control access to and from subnets and [plenty more](https://aws.amazon.com/vpc/#highlights).

But you've probably already decided if VPC is for you. There's certainly more complexity involved compared to EC2-Classic, but in my opinion it's well worth the effort.

In this guide I'll explain how to create a VPC environment suitable for a production application. As an example, I'll use a typical web application as a pattern, so we'll have web servers, database servers, etc - but feel free to deviate from this if you need.

It'll have public and private subnets, spanning multiple availability zones, a plethora of security groups and an SSH gateway for accessing and deploying to private servers. I'll also explain how everything fits together, and talk a bit on failover and high-availability issues. Finally, I'll explain how to create and bootstrap servers in the VPC using Chef.

<!-- more -->

### Creating the VPC

Hop on the AWS Console, select your region (VPCs are region-specific) and open up the [VPC Console](https://console.aws.amazon.com/vpc/home). From the VPC Console dashboard, click _Start VPC Wizard_ (or _Get started creating a VPC_). This is a quick way to get started, although we'll be changing some of the defaults later.

With the wizard, open, you'll want to select the second option, _VPC with Public and Private Subnets_, and continue. The next screen lets you configure your subnets and the NAT instance.

<div class='info-bubble'>
<div class='heading'>A quick word on public and private subnets</div>
<p>Public subnets are designed to be publically accessible, and access the Internet directly. However, they can only do these things if they have an Elastic IP attached. Private subnets are designed never to be addressable from the Internet, but only from other instances within the VPC. They can, however, talk to the Internet via a special NAT instance.</p>

<p>In practical terms, this means you'll want the majority of your servers to live in a private subnet. Generally, the only servers you'll want in the public subnet (with an Elastic IP) are:</p>

<ul><li>a NAT instance (so servers in the private subnet can talk to the Internet)</li>
<li>an SSH gateway / bastion (so you can SSH in to your private instances)</li>
<li>web facing load balancers, or your web server if you only have one</li></ul>
</div>

On the second part of the wizard you can choose your main VPC CIDR block and configure a single public and private subnet. For your main CIDR block, you can choose any IP address you like. If your CIDR notation is a bit rusty, the `/16` indicates the latter two parts of the IP address can be used, allowing for 65,531 IPs (Amazon keeps a couple for themselves).

You can change the VPC's CIDR block to anything you want, e.g. `192.168.0.0/16`, if you'd prefer.

Next, you can configure first two subnets. By the end of this guide you'll actually have six subnets, because each subnet is bound to a particular availability zone. Therefore, to achieve proper redundancy within a region, you'll need a public and private subnet in each zone and should spread your EC2 instances across them.

Change the public subnet and place it in the first availability zone (e.g. eu-west-1a). Now change the private subnet to `10.10.10.0/24`, and also place it in the same availability zone. I like to distinguish between public and private subnets using the third decimal: if it's < 10, it's public, if it's >= 10 it's private.

The last item in the wizard is the _NAT Instance_. As explained above, this is an EC2 instance in the public subnet which is used to provide Internet access for instances in private subnets. The wizard automatically creates one for you, as an `m1.small` instance. This will do for now - later I'll explain how to create one which is a `t1.micro` instead, if you don't need much power for your NAT instance.

Now hit _Create VPC_ and wait a moment while your VPC is created.

### Create additional subnets

Now that you've got your VPC, you can now add some additional subnets. As I mentioned before, each subnet covers a single availability zone, so for full redundancy you'll want one type of subnet per availability zone. Let's do this now.

Click on _Subnets_ in the VPC menu and you'll see the two subnets created by the setup wizard. The public subnet should have a CIDR of `10.0.0.0/24` and the private a CIDR of `10.0.10.0/24`. Note, also, that they are linked to different route tables.

The setup wizard will have created two route tables (you can take a look at them, from the _Route Tables_ page). One of these routes all 0.0.0.0 traffic to the Internet Gateway - the AWS router that connects the VPC to the Internet. The second route table will route 0.0.0.0 traffic to the NAT instance, which will, in turn, send it to the Internet Gateway. You won't really need to fiddle much with these, but it's useful to know how it all fits together.

Back to the subnets! You'll want to create **four** subnets, across the remaining two availability zones - one public and one private subnet per zone. What you should end up with is something like this:

IMAGE_HERE

When you create a new subnet, it'll be attached to the default route table. This happens to be the one which routes to the NAT instance. You'll need to replace the route table on your two new public subnets. Select each one in turn, and replace the route table to the one which sends 0.0.0.0 traffic to the Internet Gateway:

IMAGE_HERE

Your subnets should now look something like this. One public and one private subnet in each availability zone, with all public subnets using the public route table, and all private subnets using the (default) private route table:

IMAGE_HERE

### Secure the NAT instance

The setup wizard only creates a _default_ security group, which allows inbound access from anything in this group, and outbound access to anywhere on any port. Let's lock this down a bit: head to the _Security Groups_ page in the VPC menu.

Create a new security group called _NATSG_, and place it in the VPC. Now configure the following inbound rules:

    Port (Service)          Source
    22 (SSH)                192.168.0.0/16
    80 (HTTP)               192.168.0.0/16
    443 (HTTPS)             192.168.0.0/16
    11371 [TCP]             192.168.0.0/16
    123 [UDP]               192.168.0.0/16

And these outbound rules:

    Port (Service)          Destination
    22 (SSH)                0.0.0.0/0
    80 (HTTP)               0.0.0.0/0
    443 (HTTPS)             0.0.0.0/0
    11371 [TCP]             0.0.0.0/0
    123 [UDP]               0.0.0.0/0

This will let servers in private subnets make outbound connections on these ports. The TCP port `11371` is required if you'll be importing any keys from keyservers (e.g. using `gpg`, when adding custom PPAs in Ubuntu). If your private servers will need to connect on other other ports, make sure to specify them here. The UDP port `123` is used by NTP.

If you ever use the git protocol (e.g. `git ls-remote git://github.com/yourcompany/yourapp.git master`), you'll need to add this port to the NATSG group too. If you only ever use Git over HTTP or SSH then this isn't necessary, but it's worth remembering because, if you use Chef/Puppet, some community cookbooks might use the Git protocol and you'll find them mysteriously failing because of this port :)

    Inbound:
    9418 [TCP]              192.168.0.0/16

    Outbound:
    9414 [TCP]              0.0.0.0/0

Now you'll want to apply the NATSG group to your NAT instance. Head over to the EC2 Console, find your NAT instance, and attach the NATSG group to it (and remove the `default` group).

#### (Optional) Create a new NAT instance as a t1.micro

The setup wizard creates an NAT EC2 instance as an `m1.small`. This is fine, but you may prefer to use a `t1.micro` for your NAT instance instead, to save money. I haven't noticed any detrimental effects from using a `t1.micro` as a NAT, but if your private servers will be doing a _lot_ of constant, outbound Internet access, you may need the `m1.small` or above.

Let's start by creating a new EC2 instance. There's an AMI ID for this, `ami-1de2d969`, but the easiest way is to right click the NAT instance the setup wizard created and hit _Launch More Like This_. Then change the instance type to a Micro and make sure you launch it into the same subnet as the existing NAT instance (which should be `10.0.0.0/24`).

IMAGE_HERE

When it comes to choosing a security group, select the NATSG group you created earlier. Everything else can be left as default.

While the new instance is booting, terminate the original NAT instance. Once it has been terminated, go to the _Elastic IPs_ page. You should still have an IP here, left from the original NAT instance (if not, simply create a new one). Right click on this IP and associate it with your new NAT instance.

Disable Source/Destination check for the new NAT instance. Right click on the new NAT instance and click `Change Source/Dest. Check` and then click `Disable`.

The last thing we need to do is adjust our route table. Go back to the VPC Console, and click _Route Tables_ in the menu. Select the _Main_ route table (it should say it's associated with 0 Subnets) and remove the route to the old NAT instance (it should have a _blackhole_ status). Now add a new route:

    Destination           Target
    0.0.0.0/0             <Enter Instance ID>

Use the new NAT instance as the target. Save it, and the status should be _active_. And we're done.

### Create an SSH Gateway

A side effect of hiding away all your servers in a private subnet is that you can no longer access them from outside the VPC. Therefore we need an SSH gateway (or Bastion server, as some call it) in the public subnet, with an Elastic IP, which is allowed to SSH into your private instances.

Alternatively, you can set up a VPN connection into your VPC, which will allow you to hop on a VPN and access all your VPC servers locally. This does cost money while you are connected, but may be a better option depending on your circumstances.

#### Security group

Before creating the SSH gateway, let's create an appropriate VPC security group. Make sure you're in the VPC Console and create a new security group in the VPC called `ssh-gateway` with the following inbound rule:

    Port (Service)        Source
    22                    0.0.0.0/0

#### EC2 instance

Using your AMI of choice, create an EC2 instance for the SSH gateway. For most purposes, a `t1.micro` will work fine. Make sure you place the instance in a public subnet and place it in the `ssh-gateway` security group we just created.

If you do use an `m1.small` or above, I recommend using an instance-store backed AMI, instead of EBS. If EBS experiences any problems the last thing you want is to have problems with your SSH gateway, and you won't be storing anything important on it anyway. You can find instance-store backed Ubuntu AMI's on their [AMI Locator page](https://cloud-images.ubuntu.com/locator/ec2/).

Once your SSH gateway instance has booted, create a new Elastic IP in the VPC and associate it. You should now be able to SSH into the gateway using your AWS private key.

<div class='info-bubble'>
  <div class='heading'>Provisioning your SSH Gateway</div>
  <p>If you use Chef, Puppet or something else to provision your servers, you should include the SSH gateway as part of your automation routine. You'll want all your active sysadmins to have an account on this machine, with their public keys for password-less access.</p>
  <p>If you don't provision your servers, you should add the necessary users to the SSH gateway manually and then save it as a custom AMI, so that you can quickly create a new gateway with the correct user accounts ready to go.</p>
  <p>You'll also want to have your <em>deploy</em> user on this machine, as you'll be deploying through it, but we'll cover that in more detail later.</p>
</div>

Now that your SSH gateway is operational, with an Elastic IP, you may want to create a DNS record on your domain, as you'll be referencing it all over the place. For example, a CNAME like:

    gateway.ec2.example.com -> ec2-54-229-10-110.eu-west-1.compute.amazonaws.com.

### Create servers in the private subnet

With our gateway set up, we're ready to create some private servers. The first thing we need to do is create an `internal-ssh` security group to allow our servers to be accessed from the SSH gateway. So, from the VPC console, create a new security group called `internal-ssh` with the following inbound route:

    Port (Service)        Source
    22 (SSH)              <ID of ssh-gateway security group>

The ID the ssh-gateway will look something like `sg-d2bf58ba`. We use an ID here instead of an instance so that we can add more SSH gateways (e.g. in different subnets) without having to update our security groups.

Now you can create EC2 instances, place them in a _private_ subnet (e.g. `10.0.10.0`) and, assuming you add them to the `internal-ssh` group, can access them through the SSH gateway.

You can create these instances however you wish. If you're using Chef, I have a post on [creating EC2 instances in a VPC using Chef & Knife](/2013/05/creating-ec2-instances-in-a-vpc-using-chef-and-knife/) which may be helpful.
