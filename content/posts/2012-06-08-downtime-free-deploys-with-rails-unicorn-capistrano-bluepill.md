---
title: "Downtime-free deploys with Rails, Unicorn, Capistrano & Bluepill"
description: A guide to downtime-free production setup using Rails, Unicorn, Capistrano and Bluepill
created_at: 2012-06-08 15:50:53 +0100
kind: article
published: false
---

You've got a Rails app, and you want to deploy it behind a colourful army of Unicorns. You want to deploy and manage the whole thing easily using Capistrano, and you want Bluepill to monitor your services and keep them alive. And you want to restart your unicorn workers after a deploy without any dropped connections.

In this guide I'll expain how to do the above, with nginx configured to serve static files (and reverse-proxy app requests to Unicorn). I'm writing this from a Ubuntu perspective, but it should be transferrable to any system.

<!-- more -->

