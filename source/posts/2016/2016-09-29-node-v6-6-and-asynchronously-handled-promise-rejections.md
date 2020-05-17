---
title: Node v6.6 and asynchronously handled promise rejections
slug: node-v6-6-and-asynchronously-handled-promise-rejections
date: 2016-09-29 23:20:38 +0000
tags:
published: true
---

[Node v6.6.0](https://nodejs.org/en/blog/release/v6.6.0/) added a neat warning when it detects an unhandled promise rejection. For example:

```javascript
Promise.resolve().then(() => {
  undefinedVariable * 5;
});
// (node:57413) UnhandledPromiseRejectionWarning:
//   Unhandled promise rejection (rejection id: 20): ReferenceError: undefinedVariable is not defined
```

Prior to this warning, the `ReferenceError` would get swallowed up and you might be left scratching your head. It was possible to capture these unhandled rejections through other means, but it's great to have it built-in to Node now.

If you're seeing this warning on its own, then it's most likely legitimate and you should try to track it down.

There is, however, a counterpart to the above warning, which is:

```
PromiseRejectionHandledWarning: Promise rejection was handled asynchronously
```

This will be raised if you actually _do_ handle the rejection, but in a later tick. This pattern isn't very common in most applications, but you might encounter it in your test suite.

The culprit for me were some [Sinon.JS](https://sinonjs.org) stubs which were doing this:

```javascript
sinon.stub(Database, "connect").returns(Promise.reject("nope"));
```

Although valid - the rejection is raised as part of the test and then handled - it raises the warning because Node has no way to know that it'll be handled later on in the test. Instead, you'd get the `PromiseRejectionHandledWarning` warning a few ticks later as an acknowledgement.

The quick fix for me - and something I probably should have done a while ago - was to include the [sinon-as-promised](https://www.npmjs.com/package/sinon-as-promised) module which adds proper `resolves()` and `rejects()` functions to stubs. These don't raise any warnings because the promise rejection is created when the function is actually called.
