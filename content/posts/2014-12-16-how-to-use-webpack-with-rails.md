---
title: "What you need to know about using webpack with Rails"
created_at: 2014-12-16 08:38:00 +0000
kind: article
published: false
---

[webpack](https://webpack.github.io) is a powerful module bundler, primarily designed for front-end development, which can integrate nicely with [bower](http://bower.io) and [npm](https://www.npmjs.com/) JavaScript modules.

It has quite a few advantages over the typical Rails methods of managing front-end JS, but can still slot in seamlessly with Sprockets and the asset pipeline. Unfortunately, the documentation for webpack is still a bit hard to digest, especially if you're wanting to integrate it with Rails.

If you're still not sold on using webpack, here's some of what it can do for you:

- manage all your front-end JS (& their dependencies) using NPM or Bower
- automatically preprocess CoffeeScript, ES6, etc
- output source maps for absolutely everything, with minimal effort
- help you separate the JS for different pages into different files, but with 'common' modules shared across all pages
- split off large modules into separate files which are only downloaded on demand (via `require.ensure`)

If that sounds good to you, read on to see how to use all this with either an existing Rails app or a brand new one.

<!-- more -->

### Getting started

#### Is webpack right for your app?

webpack really is an awesome and powerful tool. But to use it effectively you need to really buy in to the whole "JS as modules" philosophy. When you're working with popular libraries like jQuery, Backbone.js, etc this is easy. But you should know going in that, especially if you're converting a large app to use webpack, you're going to hit some bumps along the way.

Typical problems you'll run in to are:

- modules which don't have a well-defined entry point (so webpack doesn't know what to include when you require it)
- modules with invalid package.json/bower.json files
- modules which simply stick something on `window.` and call it a day
- modules which add something to jQuery, instead of exporting anything
- modules which, by default, give you a gigantic kitchen sink you don't need

Fortunately all of these are solvable with webpack, which has a variety of methods for dealing with the above issues. The webpack documentation, as mentioned, is a bit light on details, but I'll cover how to fix all of the above later on.

So, is it right for your app?

**I'm just starting a new Rails app**<br>
If you forsee a significant amount of JS use, then absolutely - there's no reason not to try it!

**My app is large, but we don't have much JS (just a bit of jQuery, retina.js, etc)**<br>
Probably not worth it. webpack really shines when you're using a lot of modules and have a significant amount of your own JS code to work with too. If your combined use of JS amounts to a few `<script src='...'></script>` tags you won't see much benefit.

**My app is large, but our JS is fairly well organised and doesn't cause many issues**<br>
Moving everything to webpack is a somewhat time consuming endeavor, so it might not be worth it.

**My app is large, our JS is a land of spaghetti and everyone downloads a 800KB application.js file**<br>
You'll probably benefit from moving to webpack! It'll take some work, but this guide will tell you almost everything you need to know.

If you're ready to get started, let's move on to preparing a Rails app for webpack.

### Preparing Rails for webpack

*There aren't really any best practices for integrating webpack with Rails, so almost all of this is quite opinionated. If you don't like where I've put a directory, just place it somewhere else instead.*

#### Untangling Sprockets

The first thing to do is empty out your `app/assets/javascripts` directory. We'll be configuring webpack to output its bundles here, so they can then be picked up by Sprockets. All our actual JS code will live elsewhere.

You'll should also add this to your `.gitignore`:

    /app/assets/javascripts

There's two reasons for this:

1. The generated bundles tend to be large, and change constantly, which would generate some truly epic gitspam if you were to check them in
2. We'll be integrating webpack with our deloy process later, which will build a production version of the bundles and placing them here. So, even if you checked in the bundles, you'd be replacing them during deploy anyway.

*The above advice is intended for when you go "all in" with webpack. You can, of course, use webpack alongside some Sprockets JS bundles. If that's the case, amend the `.gitignore` to ignore only generated JS, e.g. `/app/assets/javascripts/bundle-*`*

#### A new home for your JavaScript

Because `app/assets/javascripts` is now for generated bundles, you need a new home for your actual JavaScript. I like to create a new folder in the app directory, but of course you can put it anywhere:

    app/frontend/javascripts

Inside this directory you should create a file called `entry.js` - we'll revisit this later, but now just add something like:

    #!javascript
    console.log('it worked! thanks, webpack!');

### Installing webpack & Bower

#### Installing webpack

Because webpack is a node.js application, we'll need a `package.json` file in our Rails root. A simple one will do, we're only using this to manage webpack and its modules:

    #!json
    {
      "name": "my-rails-app",
      "description": "my-rails-app",
      "version": "1.0.0",
      "devDependencies": {
        "webpack": "~1.4.13",
        "expose-loader": "~0.6.0",
        "imports-loader": "~0.6.3",
        "exports-loader": "~0.6.2"
      },
      "dependencies": {}
    }

You'll see that we have `webpack` as a dependency, and I've also thrown in a few webpack loaders (we'll cover those later) which you'll probably need.

Now it's time to run `npm install` and then you should end up with a `node_modules/` folder. You do already have node.js installed, right? If not, go and install it now, and then try again :)

Next you should install webpack globally, so you can access the `webpack` command line tool.

    $ npm install -g webpack

#### Installing Bower (optional)

A nice feature in webpack is it doesn't force you to use any particular package/dependency management tool. The default is to use npm, which has many frontend modules. However, a lot of frontend libraries are only available on Bower, which is another package management tool designed for the web.

If you anticipate only needing some popular and well-maintained libraries like jQuery, underscore, lodash, etc then you might not need Bower at all, as npm could have everything you need. You can simply add your frontend dependencies into your `package.json` and install them with npm.

However, if you need access to more libraries, or you simply prefer using Bower, it's easy to set it up. First make sure the `bower` command line tool is installed:

    $ npm install -g bower

Then create a `bower.json` file in your Rails root:

    #!json
    {
      "name": "my-rails-app",
      "version": "1.0.0",
      "description": "my-rails-app",
      "dependencies": {
        "jquery": "~1.11.0",
        "lodash": "~2.4.1"
      }
    }

Here we've got a minimal `bower.json` file which specifies jQuery and lodash as dependencies. When you run `bower install` in your Rails root, bower will install these libraries into `bower_components/`, along with any dependencies they have.

*Remember that, unlikely npm, bower resolves dependencies in a flat hierarchy. So if you specify jQuery version 1.x but another of your dependencies specifies a minimum of jQuery 2.x, you'll need to resolve it yourself.*

<div class='info-bubble'>
  <div class='heading'>Using bower and npm together</div>
  <p>There's nothing stopping you in webpack from using bower and npm at the same time, each with their own set of dependencies. For example you might get jQuery and Backbone from npm, and less popular modules from Bower. In fact, the webpack documentation states that you should <a href='https://webpack.github.io/docs/usage-with-bower.html#prefer-modules-from-npm-over-bower'>prefer npm modules over bower</a>.</p>

  <p>In a nutshell, npm (CommonJS-style) modules are typically cleaner and easier for webpack to optimise, which will result in smaller bundles and faster compile times.</p>

  <p>In practice, this might not make a huge difference. In the case of large modules like `React`, it may be worth including it as a one-off from npm so webpack can optimise it a little better, but for almost everything else I recommend sticking with Bower so you have one place for all your dependencies.</p>
</div>


### Configuring webpack

It's possible to run webpack entirely from the command line with a lot of arguments, but for any remotely complex app this isn't workable, so we'll start off with a webpack configuration file.

Create the following file in your Rails root: `webpack.config.js`

    #!javascript
    var path = require('path');
    var webpack = require('webpack');

    module.exports = {
      // the base path which will be used to resolve entry points
      context: __dirname,
      // the main entry point for our application's frontend JS
      entry: './app/frontend/javascripts/entry.js',
    }

This will end up being quite a complex file, so lets start by adding the bare minimum along with an explanation of what each bit is for. As we continue through this guide we'll add more to this file as needed. The [webpack docs](https://webpack.github.io/docs/configuration.html) have an overview of most configuration properties too.

For now we only have one entry file, but that property can also accept an array or an object of named entry points, which we'll cover later on. The important thing to note is that this entry file is the "core" of your frontend JS, i.e. anything not required by this file (or a dependency of something which is required) will never end up in the compiled bundle.

The next property we'll add is `output`, which will dictate where compiled bundles end up.

    #!javascript
    output: {
      // this is our app/assets/javascripts directory, which is part of the Sprockets pipeline
      path: path.join(__dirname, 'app', 'assets', 'javascripts'),
      // the filename of the compiled bundle, e.g. app/assets/javascripts/bundle.js
      filename: 'bundle.js',
      // if the webpack code-splitting feature is enabled, this is the path it'll use to download bundles
      publicPath: '/assets',
    }

Now we'll add the `resolve` property:

    #!javascript
    resolve: {
      // tell webpack which extensions to auto search when it resolves modules. With this,
      // you'll be able to do `require('./utils')` instead of `require('./utils.js')`
      extensions: ['', '.js']
      // by default, webpack will search in `web_modules` and `node_modules`. Because we're using
      // Bower, we want it to look in there too
      modulesDirectories: [ 'node_modules', 'bower_components' ],
    }

And finally, plugins:

    #!javascript
    plugins: [
      // we need this plugin to teach webpack how to find module entry points for bower files,
      // as these may not have a package.json file
      new webpack.ResolverPlugin([
        new webpack.ResolverPlugin.DirectoryDescriptionFilePlugin('.bower.json', ['main'])
      ])
    ]




























### How many entry points is too many?

After using webpack for a bit it's easy to tell it's designed for single page JS applications, which will typically have one or two JS files which then set up and render the entire application.

Most Rails apps have different pages, and any JS on them might instead be things like:

    #!html
    <script>
      (function() {
        $('[data-show-dropdown]').on('click', function(e) {
          e.preventDefault();
          window.app.ui.showDropDown();
        })
      )();
    </script>

As your app grows you might move from having scattered function calls and event handlers to using something like Backbone.js Views to encapsulate this logic, but then you'll still have:

    #!html
    <script>
      (function() {
        var view = new window.app.views.SignupPageView({
          el: $('#signup-page')
        });
        view.render();
      )();
    </script>

This strategy can be summed up as: "have all your JS libraries loaded, and then run a tiny bit of JS in the Rails view to 'bootstrap' the page". Bit of a mouthful, but you get the idea.

Webpack is flexible enough to support that, but there is another option - if your application is suitable - which is to eschew any JS in your Rails views and have a webpack entry file for each page which needs to execute any JS. Let's compare the two strategies.

#### One entry file per page

Not having any loose JavaScript in your Rails views can be advantageous. You'll be able to change the HTML of the page without cache-busting the JS, and vice-versa. It can also encourage decoupling of your HTML and JS, because the JS will only ever exist in its own file.

However, this approach has some significant downsides too. For many Rails apps, the amount of "per-page" JavaScript might actually be just a few lines, as in our examples above with the `SignupPageView`. Forcing an additional request to load what amounts to a small handful of JS just isn't worth it.

Unless you have a small number of pages, each with a significant amount of JS, I'd advise against this option as although it may be nice in principle, it'll actually create more work and overheads in practise.

If we were to use this strategy for our above example, you'd have multiple entry files: `users_signup.js`, `users_login.js`, `photos.js`, etc.

Each file would look something like this:

    #!javascript
    var SignupView = require('./views/users/signup');
    var view = new SignupView();
    view.render({
      el: $('[data-view-container]')
    });

The Rails view just needs to have an element on the page with the `data-view-container` attribute, include two bundles, and we're done. No `<script>` tags necessary.

    <%= javascript_include_tag 'users-signup-bundle' %>

It should be clear from this example that if you have lots of pages like this, you're going to have a bad time. So let's look at another option.

#### One entry point; some modules are exposed

For most Rails apps this is likely the best strategy. You stick with one entry point (or maybe a few more) and expose select modules to the global state (`window`) so you can then use these inside `<script>` tags.

The guideline here is to expose the bare minimum possible needed for the `<script>` tags in your Rails views. There's no point exposing all your utilities and internal modules if they're not going to be used.

For our example above, we'll want to expose our Backbone Views, as that's how we encapsulate our logic. You don't need to be using Backbone, of course. Any object can be exported and exposed, so you can use any paradigm you want.

webpack has an `expose-loader` which we can use to expose a module to the global context. There are a few ways we can use this.

The first option is to expose a global object (e.g. `$app`), and then hang our global modules (or anything else we'll need in a Rails view) off it.

    #!javascript
    // entry.js
    var $app = require('./app');

    $app.views.users.Signup = require('./views/users/signup');
    $app.views.users.Login = require('./views/users/login');

<!-- x -->

    #!javascript
    // app.js
    module.exports = {
      views = {
        users: {}
      }
    }

<!-- x -->

    #!coffeescript
    # ./views/users/signup.coffee
    module.exports = class SignupView extends Backbone.View
      initialize: ->
        # do awesome things

The next thing we'll need to do is expose our `app` module. We can do this using a loader:

    #!javascript
    loaders: [
      {
        test: path.join(__dirname, 'app', 'frontend', 'javascripts', 'app.js'),
        loader: 'expose?$app'
      },
    ]

This will add the `module.exports` of the `app.js` module to `window.$app`, to be used by any `<script>` tag in a Rails view:

    #!html
    <script>
      (function() {
        var view = new $app.views.users.Signup({ el: $('#signup-page') });
        view.render();
      })();
    </script>

Now we have a tidy global context, with the bare minimum exposed. The `app` object is currently quite simple, but could be extended to bootstrap anything which is on every page. For example we could turn the `app` object into a singleton:

    #!javascript
    // app.js
    var App = function() {
      this.views = {
        users: {}
      };
    }

    App.prototype.start = function() {
      // send CSRF tokens for all ajax requests
      $.ajaxSetup({
        beforeSend: function(xhr) {
          xhr.setRequestHeader('X-CSRF-Token', $('meta[name="csrf-token"]').attr('content'));
        }
      });
    }

    module.exports = new App();

If you don't need a complex `app` object, you could instead export an object from the `entry.js`, and expose that as `$app` - skipping the extra `app.js` module entirely.

#### A mix of multiple entry points and exposing modules

As a corollary to the above, in certain larger Rails applications it may make sense to create multiple entry points. The simplest example would be "public" areas (e.g. landing page, sign up page) and "authed" areas (the areas of your app only accessible when someone is logged in).

The authenticated areas of your app may have far more JS than the public areas, so why not have two entry points so that public pages can download a smaller bundle?

There's nothing stopping you from doing this with Sprockets, e.g. `javascripts/public-application.js` and `javascripts/private-application.js`, but `webpack` has a neat trick to figure out shared module dependencies and put them in a common JS file.

For example, it's highly likely that both your public and private areas will need jQuery. Of course, with Sprockets you could create a third JS file, `javascripts/shared-dependencies.js`, but webpack will do this automatically for you by analysing your code, and will always create the optimum common file. If you stopped using a certain module in one entry file, webpack would no longer add it to the common file.

It's easy to enable this feature by adding the `CommonsChunkPlugin` to your plugins list:

    #!javascript
    plugins: [
      new webpack.optimize.CommonsChunkPlugin('common-bundle.js')
    ]

This will create a new file in your output directly called `common-bundle.js`, which will contain the (tiny) webpack bootstrap code, plus any modules webpack detected are in use by more than one entry point. You can then just include this script on each page, alongside the normal entry file:

    #!erb
    <%= javascript_include_tag 'common-bundle' %>
    <%= javascript_include_tag 'public-bundle' %>

### The advantages of modules

