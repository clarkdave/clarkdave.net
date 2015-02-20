---
title: "easyXDM, CoffeeScript & async RPCs"
slug: easyxdm-cofeescript-and-async-rpcs
date: 2012-09-17 01:18:40 +0200
kind: article
published: true
---

While using this bundle of techs I hit a curious problem. I had a RPC declaration on my producer which looked something like this:

``` coffeescript
local:
  sendPost: (post, fn, errorFn) ->
    $.ajax
      type: 'post'
      url: '/posts'
      dataType: 'json'
      data:
        post: post
      success: (data) ->
        fn data
```

And in my consumer I had this:

``` coffeescript
rpc.sendPost post, (data) ->
  if data.accepted
    alert 'Post was accepted'
  else
    alert 'Post not accepted'
```

You'd expect the callback in that call to trigger once the ajax request finished back on the producer. However, the callback fires immediately and you'd actually get a error: `Uncaught TypeError: Cannot read property 'accepted' of undefined`

The reason is so simple I almost forgot it could happen: CoffeeScript always adds a *return* to your functions. But easyXDM explicitly looks for a return value in an RPC function and, if it gets one, it'll run your callback immediately. So in this case, CoffeeScript is causing the $.ajax method itself to be returned, which means an object like this: `{ readyState: 1 }`. Not so good.

Luckily it's easy to stop CoffeeScript from doing this: simply add either 'return' or 'undefined' as the last statement in the function, and easyXDM will wait for the callback instead. Be sure to comment this, because otherwise it'll probably look like a mistake ;)
