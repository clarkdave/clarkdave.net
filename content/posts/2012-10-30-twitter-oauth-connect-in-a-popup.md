---
title: "Twitter OAuth authorisation in a popup"
created_at: 2012-10-30 07:59:48 +0100
kind: article
published: false
---

It's pretty common these days to let your users either sign up with or connect to Twitter from within your application. The typical way to do this is to redirect the user to Twitter, have them authorise and then bring them back.

Although this works fine, I wanted this to take place in a popup window, which avoids having the user leave your page and also means the whole thing can be handled in Javascript (invite the user to connect, wait for them to finish, and then act accordingly without a page refresh).

Facebook has a handy Javascript SDK for this situation and it works great. With Twitter, we need to do this manually, but even so it's not too difficult. I'll explain how to do this using the Ruby Omniauth gem, but it'll be easy to adapt for other libraries.

<!-- more -->

### Overview

What makes this tick is actually pretty simple:

  1. User clicks 'Connect with Twitter' and you open a popup window to the Twitter OAuth URL
  3. User authorises the app and is redirected back to your server
  4. The page the user is redirected back to does `window.close()`
  5. Your original page checks periodically to see if the window has closed
  6. When it has closed, make a call to your server to verify if the user has now connected

### The popup

We'll create a TwitterConnect class to keep all this tidy:

    #!javascript
    var TwitterConnect = (function() {

      function TwitterConnect() {}

      TwitterConnect.prototype.initialize = function(auth_url) {
        this.url = url;
      }

      TwitterConnect.prototype.start = function(fn)
    })