---
title: "Creating and bootstrapping EC2 instances in a VPC using Chef & Knife"
created_at: 2013-05-09 09:02:41 +0100
kind: article
published: true
---

Instances in an Amazon VPC are a little tricker than usual to create using the `knife ec2 server create` command, because they are, of course, private. However, if you have an SSH gateway you can use that to create and bootstrap them.

There is one small caveat, however: if you create a server in a **public** subnet, it will not be able to access the Internet (and thus complete the Chef bootstrap process) until you assign it an Elastic IP. The `knife ec2` plugin doesn't let you do this, so you'll either have to do it manually after the server has been created, or script it using the AWS API.

<!-- more -->

### Creating a server

You'll need:

* an SSH gateway in the VPC, accessible from the Internet
  * you should have a user account on this gateway, preferably with public key authentication
* the ID of the subnet you intend to deploy into
* the AMI you wish to use
* the security group IDs for the new instance
  * one of these must contain a rule which allows inbound SSH access from the SSH gateway

If you have all that, you can use the following command. It's a bit of a mouthful:

    knife ec2 server create 
      --image ami-ce7b6fba
      --flavor m1.small
      --region eu-west-1
      --server-connect-attribute private_ip_address
      --ssh-gateway user@gateway.ec2.example.com
      --ssh-user ubuntu
      --identity-file ~/.ssh/clarkdave.pem
      --subnet subnet-8d034be5
      --environment production
      --node-name web1
      --run-list 'role[base],role[web_server]'

To explain a few of the arguments:

* `--server-connect-attribute`: after the instance is created, Knife will use this attribute to find an IP address to connect to. Because VPC instances don't have a public IP by default, we use the `private_ip_address` instead
* `--ssh-gateway`: don't forget to specify the user (e.g. user@gateway...), or everything could fail with unhelpful errors
  * I have only tested this with a user who has public key authentication. The command may not be smart enough to prompt for a password for the SSH gateway, so if it fails, that could be why
* `--ssh-user`: this is the user Chef will connect with to bootstrap the new instance. For Amazon AMI's it's usually `ec2-user`

Assuming all the options were correct, Chef should now create and then proceed to bootstrap the server. As I mentioned in the intro, if this server is in a public subnet, you'll need to give it an Elastic IP because the bootstrap can proceed (it will just sit there timing out otherwise, while it attempts to download Chef).

### Bootstrapping a server

If you already have a server in the VPC, you can also bootstrap it using the SSH gateway:

    knife bootstrap 10.0.10.245
      --ssh-gateway user@gateway.ec2.example.com
      --ssh-user ubuntu
      --sudo
      --identity-file ~/.ssh/clarkdave.pem
      --environment production
      --node-name web1
      --run-list 'role[base],role[web_server]'

And that's all there is to it!