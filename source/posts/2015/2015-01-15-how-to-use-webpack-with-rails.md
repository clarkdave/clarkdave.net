---
title: "What you need to know about using webpack with Rails"
slug: what-you-need-to-know-about-using-webpack-with-rails
date: 2015-01-15 08:38:00 +0000
kind: article
published: false
---

[webpack](https://webpack.github.io) is a powerful module bundler, primarily designed for front-end development, which can integrate nicely with [bower](http://bower.io) and [npm](https://www.npmjs.com/) JavaScript modules.

It has quite a few advantages over the typical Rails methods of managing front-end JS, but can still slot in seamlessly with Sprockets and the asset pipeline. Unfortunately, the documentation for webpack is still a bit hard to digest, especially if you're wanting to integrate it with Rails.

If you're still not sold on using webpack, here's some of what it can do for you:

- manage all your front-end JS (& their dependencies) using NPM or Bower
- automatically preprocess CoffeeScript, ES6, etc
- output source maps for absolutely everything, with minimal effort
- help you separate the JS for different pages into different files, with 'common' modules automatically shared across all pages
- split off large modules into separate files which are only downloaded on demand (via `require.ensure`)

If that sounds good to you, read on to see how to use all this with either an existing Rails app or a brand new one. By the way, although this is Rails specific, some of what's here might be of benefit when combining webpack with any Rails-like framework.

<!-- more -->

### Getting started

#### Is webpack right for your app?

webpack really is an awesome and powerful tool. But to use it effectively you need to really buy in to the whole "JS as modules" philosophy. When you're working with popular libraries like jQuery, Backbone.js, etc this is easy. But you should know going in that, especially if you're converting a large app to use webpack, you're going to hit some bumps along the way.

Typical problems you'll run in to are:

- modules which don't have a well-defined entry point (webpack won't know what to include when you require it)
- modules with invalid package.json/bower.json files
- modules which simply stick something on `window` and call it a day
- modules which add something to jQuery, instead of exporting anything
- modules which, by default, give you a gigantic kitchen sink you don't need

Fortunately all of these are solvable with webpack, which has a variety of methods for dealing with the above issues. The webpack documentation, as mentioned, is a bit light on details, but I'll cover how to fix all of the above later on.

So, is it right for your app?

**I'm just starting a new Rails app**<br>
If you forsee a significant amount of JS use, then absolutely - there's no reason not to try it!

**My app is large, but we don't have much JS (just a bit of jQuery, retina.js, etc)**<br>
Probably not worth it. webpack really shines when you're using a lot of modules and have a significant amount of your own JS code to work with too. If your total use of JS amounts to a few `<script src='...'>` tags you won't see much benefit.

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

``` javascript
var _ = require('lodash');
_.times(5, function(i) {
  console.log(i);
});
```

### Installing webpack & Bower

#### Installing webpack

Because webpack is a node.js application, we'll need a `package.json` file in our Rails root. A simple one will do, we're only using this to manage webpack and its modules:

``` json
{
  "name": "my-rails-app",
  "description": "my-rails-app",
  "version": "1.0.0",
  "devDependencies": {
    "webpack": "~1.4.13",
    "expose-loader": "~0.6.0",
    "imports-loader": "~0.6.3",
    "exports-loader": "~0.6.2",
    "lodash": "~2.4.1"
  },
  "dependencies": {}
}
```

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

``` json
{
  "name": "my-rails-app",
  "version": "1.0.0",
  "description": "my-rails-app",
  "dependencies": {
    "jquery": "~1.11.0",
    "lodash": "~2.4.1"
  }
}
```

Here we've got a minimal `bower.json` file which specifies jQuery and lodash as dependencies. When you run `bower install` in your Rails root, bower will install these libraries into `bower_components/`, along with any dependencies they have.

*Remember that, unlike npm, bower resolves dependencies in a flat hierarchy. So if you specify jQuery version 1.x but another of your dependencies specifies a minimum of jQuery 2.x, you'll need to resolve this yourself.*

<div class='info-bubble'>
  <div class='heading'>Using bower and npm together</div>
  <p>There's nothing stopping you in webpack from using bower and npm at the same time, each with their own set of dependencies. For example you might get jQuery and Backbone from npm, and less popular modules from Bower. In fact, the webpack documentation states that you should <a href='https://webpack.github.io/docs/usage-with-bower.html#prefer-modules-from-npm-over-bower'>prefer npm modules over bower</a>.</p>

  <p>In a nutshell, npm (CommonJS-style) modules are typically cleaner and easier for webpack to optimise, which will result in smaller bundles and faster compile times.</p>

  <p>In practice, this might not make a huge difference. In the case of large modules like `React`, it may be worth including it as a one-off from npm so webpack can optimise it a little better, but for almost everything else I recommend sticking with Bower so you have one place for all your dependencies.</p>
</div>


### Configuring webpack

It's possible to run webpack entirely from the command line with a lot of arguments, but for any remotely complex app this isn't workable, so we'll start off with a webpack configuration file.

Create the following file in your Rails root: `webpack.config.js`

``` javascript
var path = require('path');
var webpack = require('webpack');

var config = module.exports = {
  // the base path which will be used to resolve entry points
  context: __dirname,
  // the main entry point for our application's frontend JS
  entry: './app/frontend/javascripts/entry.js',
};
```

This will end up being quite a complex file, so lets start by adding the bare minimum along with an explanation of what each bit is for. As we continue through this guide we'll add more to this file as needed. The [webpack docs](https://webpack.github.io/docs/configuration.html) have an overview of most configuration properties too.

For now we only have one entry file, but that property can also accept an array or an object of named entry points, which we'll cover later on. The important thing to note is that this entry file is the "core" of your frontend JS, i.e. anything not required by this file (or a dependency of something which is required) will never end up in the compiled bundle.

The next property we'll add is `output`, which will dictate where compiled bundles end up.

``` javascript
config.output = {
  // this is our app/assets/javascripts directory, which is part of the Sprockets pipeline
  path: path.join(__dirname, 'app', 'assets', 'javascripts'),
  // the filename of the compiled bundle, e.g. app/assets/javascripts/bundle.js
  filename: 'bundle.js',
  // if the webpack code-splitting feature is enabled, this is the path it'll use to download bundles
  publicPath: '/assets',
};
```

Now we'll add the `resolve` property:

``` javascript
config.resolve = {
  // tell webpack which extensions to auto search when it resolves modules. With this,
  // you'll be able to do `require('./utils')` instead of `require('./utils.js')`
  extensions: ['', '.js'],
  // by default, webpack will search in `web_modules` and `node_modules`. Because we're using
  // Bower, we want it to look in there too
  modulesDirectories: [ 'node_modules', 'bower_components' ],
};
```

And finally, `plugins`:

``` javascript
config.plugins = [
  // we need this plugin to teach webpack how to find module entry points for bower files,
  // as these may not have a package.json file
  new webpack.ResolverPlugin([
    new webpack.ResolverPlugin.DirectoryDescriptionFilePlugin('.bower.json', ['main'])
  ])
];
```

### Running webpack

Before we can run webpack, we need to make sure our Bower dependencies are installed. If you've opted to only use NPM, then running `npm install` is all you need to do. To install Bower dependencies:

    $ bower install

You should now have a `bower_components/` directory with `jquery` and `lodash` (if you used the example bower.conf from above).

Now that's done, we can run webpack to see if everything is working. From your Rails root, run:

    $ webpack -d --display-reasons --display-chunks --progress

This command runs webpack once in development mode, and asks it to tell you what it's doing. We'll eventually automate this command. If everything went well, you should see some output like this:

    Hash: cfee07d10692c4ab1eeb
    Version: webpack 1.4.14
    Time: 548ms
            Asset    Size  Chunks             Chunk Names
        bundle.js  254088       0  [emitted]  main
    bundle.js.map  299596       0  [emitted]  main
    chunk    {0} bundle.js, bundle.js.map (main) 244421 [rendered]
        [0] ./app/frontend/javascripts/entry.js 73 {0} [built]
         + 2 hidden modules

This tells you webpack has created a "chunk" called `bundle.js`, plus an accompanying sourcemap. Chunks are how webpack splits up your JavaScript. For now, it'll just create one chunk per entry point. However, if you have any shared modules between entry points, or use the code-splitting feature (discussed later), webpack may create multiple chunks with names like `1.1-bundle.js`.

#### The compiled webpack bundle

If you now open up `app/assets/javascripts/bundle.js`, you'll see your compiled JavaScript. This file contains a tiny (a few hundred bytes) webpack loader which is used to orchestrate all your modules and provide them with the ability to `require` their dependencies, as standard JavaScript doesn't have this functionality.

What webpack actually does is look through your code and replace any calls to, e.g. `require('lodash')` with something like this:

``` javascript
var _ = __webpack_require__(/*! lodash */ 1);
```

The `__webpack_require__` function, which is injected in to every module, can then load the requested dependency. If you're following along with our examples, you should have your entry module listed around line *~50*, looking something like this:

``` javascript
/* 0 */
/*!*******************************************!*\
  !*** ./app/frontend/javascripts/entry.js ***!
  \*******************************************/
/***/ function(module, exports, __webpack_require__) {

  var _ = __webpack_require__(/*! lodash */ 1);
  _.times(5, function(i) {
    console.log(i);
  });
```

#### Including webpack bundles in Rails views

As you'd expect, you simply include the compiled JavaScript bundle as normal:

```erb
<%= javascript_include_tag 'bundle'  %>
```

Now we've got the basics down, let's cover some more features which are likely to be necessary in any large application.

### Exposing global modules (e.g. jQuery)

By now you should have the idea of `require`. In a particular module, if you want to use jQuery you can write

``` javascript
$ = require('jquery');
$('p').show();
```

However, you may want to

1. Automatically expose jQuery to every module, so you don't have to write `$ = require('jquery')` every time
2. Expose jQuery as a global variable, e.g. `window.$`, so it can be used outside of modules. If you plan on having any "loose" JavaScript in your Rails views, this could be essential

Both these are possible with webpack, though the documentation can make it a little hard to grok how. To tackle the first - exposing jQuery to every module - we'll use the `ProvidePlugin`. So, add this to your webpack config's plugins array:

``` javascript
new webpack.ProvidePlugin({
  $: 'jquery',
  jQuery: 'jquery',
})
```

This will now automatically inject the `$` and `jQuery` variables into every module, so you no longer need to `require` them.

For the second step - exposing jQuery to `window` - we need to add a [loader](https://webpack.github.io/docs/loaders.html). In webpack, loaders apply some kind of transformation on a file. For example, later we'll show how to use a loader to transform CoffeeScript files into JavaScript.

The `expose` loader takes the exports from a module and adds it to the global context, which in our case is `window`. You can configure loaders in the webpack config, which makes sense for transformations like CoffeeScript, but you can also specify them when you `require` a module, which I think makes more sense for the `expose` loader as it expresses the intent in your code.

So, at the top of your main `entry.js` file, add this line:

``` javascript
require('expose?$!expose?jQuery!jquery');
```

I know, the syntax is a bit clunky! We're actually running the `expose` loader twice here, to add jQuery to both `window.$` and `window.jQuery`.

The expose loader works like this: `require(expose?<libraryName>!<moduleName>)`, where `<libraryName>` will be `window.libraryName` and `<moduleName>` is the module you're including, in this case `jquery`. You can chain loaders by separating them with `!`, which we did above.

If you run webpack again, using the same command as before, and then view a page in your browser which includes the resulting bundle, you should see that you now have access to `$` and `jQuery` in the global scope.

### Source maps

You probably noticed webpack is automatically dropping off a `bundle.js.map` in your output directory. The source maps generated by webpack work extremely well. You get to download a single bundle (instead of 10+ individual files, which can get slow) but can view errors inside individual files, as they exist on your file system. And of course, if you're using CoffeeScript and friends, you can view errors in the context of the actual CoffeeScript file.

However, by default Sprockets will break the source maps by appending a semi-colon to them, so browsers can't parse them. You can fix this with the following configuration option:

``` ruby
Rails.application.config.assets.configure do |env|
  env.unregister_postprocessor 'application/javascript', Sprockets::SafetyColons
end
```

At this to your `config/initializers/assets.rb` (or directly in `config/application.rb` for older versions of Rails). Then clear your Sprockets cache: `$ rm -r tmp/cache`

Now when you get errors, or view loaded sources in a browser, you'll see the actual file (e.g. `entry.js`) instead of the giant bundled file.

#### Virtual source paths

In Chrome, by default the source map generated by webpack will put everything in a 'pseudo path', `webpack://`, when you view it in the inspector's *Sources* tab. You can make this a bit nicer by adding the following to your webpack `config.output`:

    devtoolModuleFilenameTemplate: '[resourcePath]',
    devtoolFallbackModuleFilenameTemplate: '[resourcePath]?[hash]',

Now your 'virtual' source files will appear under the `domain > assets` directory in the Sources tab.

<div class='info-bubble'>
  <div class='heading'>Sprockets cache and source maps</div>
  <p>In my experience, Sprockets can be very aggressive at caching source maps. If they ever start acting weird, make sure to clear the sprockets cache in <code>tmp/cache</code> first.</p>
</div>

### Loading CoffeeScript and other transpiled languages

We can use a loader to automatically transpile modules written in CoffeeScript or similar. As with the `expose` loader (explained above), this can be done inside the `require` statement, but it's far nicer to add this loader to the webpack config so we can then require CoffeeScript modules as though they were ordinary JS.

First, install and add the `coffee-loader` module to your `package.json`, like this:

    $ npm install coffee-loader@0.7.2 --save-dev

Now, in our webpack config, update the `config.resolve.extensions` list so we can require `.coffee` files without specifying an extension:

    extensions: ['', '.js', '.coffee']

Finally, we'll add a loader:

``` javascript
config.module = {
  loaders: [
    { test: /\.coffee$/, loader: 'coffee-loader' },
  ],
};
```

Now create a new CoffeeScript file: `app/frontend/javascripts/app.coffee`

``` coffeescript
_ = require('lodash')

module.exports = class App
  start: ->
    _.times 3, (i) -> console.log(i)
```

We can update our existing `entry.js` to require this CoffeeScript module:

``` javascript
require('expose?$!expose?jQuery!jquery');
var App = require('./app');

var app = new App();
app.start();
```

Now run webpack again and back in your browser you should see everything working as expected. If you've got source maps working (see above), you'll be able to view errors in the original CoffeeScript source too.

### Code splitting and lazily loading modules

A neat feature in webpack is its built-in mechanism for splitting certain modules out into their own JS files, to be included only when something on the page requires them. For example, suppose you are using the [Ace](http://ace.c9.io/) code editor. It's awesome, and really powerful, but it also weighs in at ~300KB. If you only use this editor in certain situations, doesn't it make sense to only load it when it's actually needed?

With webpack you can use `require.ensure` to load modules on demand. webpack will figure out which modules can be lazily loaded, and place them in their own "chunk". When your code is being used, and it hits a `require.ensure` part, webpack will take over and download the module via JSONP so your code can continue. For example:

``` javascript
function Editor() {};
Editor.prototype.open = function() {
  require.ensure(['ace'], function(require) {
    var ace = require('ace');
    var editor = ace.edit('code-editor');
    editor.setTheme('ace/theme/textmate');
    editor.gotoLine(0);
  });
};

var editor = new Editor();
$('a[data-open-editor]').on('click', function(e) {
  e.preventDefault();
  editor.open();
});
```

Although this is a somewhat contrived example, you should be able to see that we'll only be downloading and including the `ace` module when the editor is opened.

Now let's move on and think about multiple entry points and common modules, which is a great way to structure the frontend JS in a large application.

### Multiple entry points

After using webpack for a bit it's easy to tell it's designed for single page JS applications, which will typically have one or two JS files which then set up and render the entire application.

Most Rails apps have different pages, and any JS on them might instead be things like:

``` javascript
(function() {
  $('[data-show-dropdown]').on('click', function(e) {
    e.preventDefault();
    window.app.ui.showDropDown();
  })
)();
```

As your app grows you might move from having scattered function calls and event handlers to using something like Backbone.js Views to encapsulate this logic, but then you'll still have:

``` javascript
(function() {
  var view = new window.app.views.SignupPageView({
    el: $('#signup-page')
  });
  view.render();
)();
```

This strategy can be summed up as: "have all your JS libraries loaded, and then run a tiny bit of JS in the Rails view to 'bootstrap' the page". Bit of a mouthful, but you get the idea.

Webpack is flexible enough to support that, but there is another option - if your application is suitable - which is to eschew any JS in your Rails views and have a webpack entry file for each page which needs to execute any JS. Let's compare the two strategies.

#### One entry file per page

Not having any loose JavaScript in your Rails views can be advantageous. You'll be able to change the HTML of the page without cache-busting the JS, and vice-versa. It can also encourage decoupling of your HTML and JS, because the JS will only ever exist in its own file.

However, this approach has some significant downsides too. For many Rails apps, the amount of "per-page" JavaScript might actually be just a few lines, as in our examples above with the `SignupPageView`. Forcing an additional request to load what amounts to a small handful of JS just isn't worth it.

Unless you have a small number of pages, each with a significant amount of JS, I'd advise against this option as although it may be nice in principle, it'll actually create more work and overheads in practise.

If we were to use this strategy for our above example, you'd have multiple entry files: `users_signup.js`, `users_login.js`, `photos.js`, etc.

Each file would look something like this:

``` javascript
var SignupView = require('./views/users/signup');
var view = new SignupView();
view.render({
  el: $('[data-view-container]')
});
```

The Rails view just needs to have an element on the page with the `data-view-container` attribute, include two bundles, and we're done. No `<script>` tags necessary.

``` erb
<%= javascript_include_tag 'users-signup-bundle' %>
```

It should be clear from this example that if you have lots of pages like this, you're going to have a bad time. So let's look at another option.

#### One entry point; some modules are exposed

For most Rails apps this is likely the best strategy. You stick with one entry point (or maybe a few more) and expose select modules to the global state (`window`) so you can then use these inside `<script>` tags.

The guideline here is to expose the bare minimum possible needed for the `<script>` tags in your Rails views. There's no point exposing all your utilities and internal modules if they're not going to be used.

For our example above, we'll want to expose our Backbone Views, as that's how we encapsulate our logic. You don't need to be using Backbone, of course. Any object can be exported and exposed, so you can use any paradigm you want.

Using webpack's `expose-loader` we can expose a module to the global context. There are a few ways we can use this.

The first option is to expose a global object (e.g. `$app`), and then hang our global modules (or anything else we'll need in a Rails view) off it.

``` javascript
// entry.js
var $app = require('./app');

$app.views.users.Signup = require('./views/users/signup');
$app.views.users.Login = require('./views/users/login');
```

<!-- x -->

``` javascript
// app.js
module.exports = {
  views = {
    users: {}
  }
}
```

<!-- x -->

``` coffeescript
# ./views/users/signup.coffee
module.exports = class SignupView extends Backbone.View
  initialize: ->
    # do awesome things
```

The next thing we'll need to do is expose our `app` module. We can do this using a loader:

``` javascript
loaders: [
  {
    test: path.join(__dirname, 'app', 'frontend', 'javascripts', 'app.js'),
    loader: 'expose?$app'
  },
]
```

This will add the `module.exports` of the `app.js` module to `window.$app`, to be used by any `<script>` tag in a Rails view:

``` javascript
(function() {
  var view = new $app.views.users.Signup({ el: $('#signup-page') });
  view.render();
})();
```

Now we have a tidy global context, with the bare minimum exposed. The `app` object is currently quite simple, but could be extended to bootstrap anything which is on every page. For example we could turn the `app` object into a singleton:

``` javascript
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
```

If you don't need a complex `app` object, you could instead export an object from the `entry.js`, and expose that as `$app` - skipping the extra `app.js` module entirely.

#### A mix of multiple entry points and exposing modules

As an addition to the above, in larger Rails applications it may make sense to create multiple entry points. The simplest example would be "public" areas (e.g. landing page, sign up page) and "authed" areas (the areas of your app only accessible when someone is logged in).

The authenticated areas of your app may have far more JS than the public areas, so why not have two entry points so that public pages can download a smaller bundle?

There's nothing stopping you from doing this with Sprockets, e.g. `javascripts/public-application.js` and `javascripts/private-application.js`, but `webpack` has a neat trick to figure out shared module dependencies and put them in a common JS file.

For example, it's highly likely that both your public and private areas will need jQuery. Of course, with Sprockets you could create a third JS file, `javascripts/shared-dependencies.js`, but webpack will do this automatically for you by analysing your code, and will always create the optimum common file. If you stopped using a certain module in one entry file, webpack would no longer add it to the common file.

It's easy to enable this feature by adding the `CommonsChunkPlugin` to your plugins list:

``` javascript
plugins: [
  new webpack.optimize.CommonsChunkPlugin('common-bundle.js')
]
```

This will create a new file in your output directly called `common-bundle.js`, which will contain the (tiny) webpack bootstrap code, plus any modules webpack detected are in use by more than one entry point. You can then just include this script on each page, alongside the normal entry file:

``` erb
<%= javascript_include_tag 'common-bundle' %>
<%= javascript_include_tag 'public-bundle' %>
```

### Using webpack in production

Everything we've covered so far should be enough to get you up and running with webpack and Rails, but there's a few more things you'll need to do to get webpack ready for use in a production environment.

In particular, when deploying your Rails app to production you'll want your JS to be minified and all the files to have a cache digest added (like Sprockets does automatically), so you can set far future expire headers.

webpack supports minification and cache digests out of the box, but we'll need to add a few extra bits to get this working with Rails.

#### Create multiple webpack configuration files

Up until now we've had a single `webpack.config.js` file. We'll want to break this up now so we can have different configurations in place for development and production environments.

Let's start by creating a 'base' config, which both our development and production configs can inherit from. Create the file `config/webpack/main.config.js`. In here you'll want all of your base config values, such as your entry points, etc. If you've been following the guide until now, this file should just be a copy of your `webpack.config.js` file.

``` javascript
var path = require('path');
var webpack = require('webpack');

var config = module.exports = {
  context: path.join(__dirname, '../', '../'),
};

var config.entry = {
  // your entry points
};

var config.output = {
  // your outputs
  // we'll be overriding some of these in the production config, to support
  // writing out bundles with digests in their filename
}
```

Now create `config/webpack/development.config.js`

``` javascript
var webpack = require('webpack');
var _ = require('lodash');
var config = module.exports = require('./main.config.js');

config = _.merge(config, {
  debug: true,
  displayErrorDetails: true,
  outputPathinfo: true,
  devtool: 'sourcemap',
});

config.plugins.push(
  new webpack.optimize.CommonsChunkPlugin('common', 'common-bundle.js')
);
```

This is our development config, so we've turned on debug mode, sourcemaps and enabled a few other options to increase webpack's verbosity.

Finally, create `config/webpack/production.config.js`

``` javascript
var webpack = require('webpack');
var ChunkManifestPlugin = require('chunk-manifest-webpack-plugin');
var _ = require('lodash');
var path = require('path');

var config = module.exports = require('./main.config.js');

config.output = _.merge(config.output, {
  path: path.join(config.context, 'public', 'assets'),
  filename: '[name]-bundle-[chunkhash].js',
  chunkFilename: '[id]-bundle-[chunkhash].js',
});

config.plugins.push(
  new webpack.optimize.CommonsChunkPlugin('common', 'common-[chunkhash].js'),
  new ChunkManifestPlugin({
    filename: 'webpack-common-manifest.json',
    manfiestVariable: 'webpackBundleManifest',
  }),
  new webpack.optimize.UglifyJsPlugin(),
  new webpack.optimize.OccurenceOrderPlugin()
);
```

In our production config, we're overriding the output configuration to write bundles with digest chunks in the name - these digests are generated automatically by webpack. We're also telling it to write these bundles in our `public/assets` folder, the same thing a `rake assets:precompile` would do.

We've also included the `ChunkManifestPlugin`, which outputs a JSON file containing numeric IDs linked to the bundle names. We'll cover why we need this in a moment. You'll also need to add this plugin to your `package.json` file as a devDependency:

    "chunk-manifest-webpack-plugin": "~0.0.1"

At the end of the config we're including the `UglifyJsPlugin`, which will minify everything, and the `OccurenceOrderPlugin`, which will shorten the IDs of modules which are included often, to reduce filesize.

#### webpack precompile

During a deploy with Rails, the `assets:precompile` task is run which bundles and minifies assets and then writes them to `public/assets` with a digest. Of course, Sprockets doesn't know about our webpack assets (and has, in fact, been instructed to ignore them) so we need a new task to do this.

You can implement this however you want, but I use a rake task: `lib/tasks/webpack.rb`

``` ruby
namespace :webpack do
  desc 'compile bundles using webpack'
  task :compile do
    cmd = 'webpack --config config/webpack/production.config.js --json'
    output = `#{cmd}`

    stats = JSON.parse(output)

    File.open('./public/assets/webpack-asset-manifest.json', 'w') do |f|
      f.write stats['assetsByChunkName'].to_json
    end
  end
end
```

It's a simple procedure! We call `webpack`, passing it our production config, and request for it to return the results as JSON object. When it's finished, we parse the returned JSON and use this to write our own "assets manifest" file, which will look similar to this:

``` json
{
  "common": "common-4cdf0a22caf53cdc8e0e.js",
  "authenticated": "authenticated-bundle-2cc1d62d375d4f4ea6a0.js",
  "public":"public-bundle-a010df1e7c55d0fb8116.js"
}
```

This has the same function as the manifest file which Sprockets creates for all its precompiled assets - it'll let our application figure out the real filename for a bundle when we include it in a view.

#### Add webpack configuration options to Rails

Open up `config/application.rb` and add this:

```ruby
config.webpack = {
  :use_manifest => false,
  :asset_manifest => {},
  :common_manifest => {},
}
```

We'll be adding some helpers in a moment which will use these configuration values. Next, create a new initializer, `config/initializers/webpack.rb`

``` ruby
if Rails.configuration.webpack[:use_manifest]
  asset_manifest = Rails.root.join('public', 'assets', 'webpack-asset-manifest.json')
  common_manifest = Rails.root.join('public', 'assets', 'webpack-common-manifest.json')

  if File.exist?(asset_manifest)
    Rails.configuration.webpack[:asset_manifest] = JSON.parse(
      File.read(asset_manifest),
    ).with_indifferent_access
  end

  if File.exist?(common_manifest)
    Rails.configuration.webpack[:common_manifest] = JSON.parse(
      File.read(common_manifest),
    ).with_indifferent_access
  end
end
```

Now, if our `webpack[:use_manifest]` is true, we'll preload the manifest file and stash it with the config for easy access later.

The next step, as you can probably guess, is to set that value to `true` for production (and any other production-like environments, like staging):

``` ruby
# config/environments/production.rb
config.webpack[:use_manifest] = true
```

#### Including precompiled assets in views

One final step - we need to write two helpers to include these assets (with their digests) in our views.

The first helper we'll call `webpack_bundle_tag`:

``` ruby
# app/helpers/application_helper.rb

def webpack_bundle_tag(bundle)
  src =
    if Rails.configuration.webpack[:use_manifest]
      manifest = Rails.configuration.webpack[:asset_manifest]
      filename = manifest[bundle]

      "#{compute_asset_host}/assets/#{filename}"
    else
      "#{compute_asset_host}/assets/#{bundle}-bundle"
    end

  javascript_include_tag(src)
end
```

This helper simply checks if we're using a manifest. If we are, it'll look up the real filename in said manifest; if not, it'll just use the standard bundle filename.

The second helper we'll call `webpack_manifest_script`. This will use the `common manifest` we mentioned earlier. To explain why we need this, it'll help to look at an example of the common manifest file:

``` json
{
  "0": "0-bundle-850438bac52260f520a1.js",
  "2": "2-bundle-15c08c5e4d1afb256c9a.js",
  "5": "authenticated-bundle-2cc1d62d375d4f4ea6a0.js"
}
```

You may remember from before that webpack creates an ID for each bundle, to minimise the size of all its files. So, every compiled bundle webpack produces will internally have an ID. By default, webpack will store these IDs in the `common` bundle. The problem with this is that whenever you change any bundle, it'll mean the `common` bundle will be updated (to include the new common manifest), thus cache-busting it needlessly.

Thanks to the [ChunkManifestPlugin](https://github.com/diurnalist/chunk-manifest-webpack-plugin), webpack can be told to **not** write this manifest directly into the common bundle. Instead it writes the manifest out and then, when it runs in the browser, will look for a global variable `webpackBundleManifest` (set in the plugin's config). So our second helper is simply going to set this variable:

``` ruby
# app/helpers/application_helper.rb

def webpack_manifest_script
  return '' unless Rails.configuration.webpack[:use_manifest]
  javascript_tag "window.webpackManifest = #{Rails.configuration.webpack[:common_manifest]}"
end
```

And we're done! In your layout you'll use these helpers like so:

``` erb
<%= webpack_manifest_script %>
<%= webpack_bundle_tag 'common' %>
<%= webpack_bundle_tag 'public' %>
```

Which, in production, will end up like:

``` html
<script>
//<![CDATA[
window.webpackManifest = {"0":"0-bundle-bdbd995368b007bb18a7.js","2":"2-bundle-7ad34cf6445d875d8506.js","3":"3-bundle-f8745c8bc2319252b6de.js","4":"4-bundle-ec8f5ae62f2e8da11aa1.js","5":"authenticated-bundle-933816ada9534488d12f.js","6":"public-bundle-8eb73d97201bd2e4951b.js"}
//]]>
</script>
<script src="https://abc.cloudfront.net/assets/common-71a050793d79ce393b1e.js"></script>
<script src="https://abc.cloudfront.net/assets/public-bundle-8eb73d97201bd2e4951b.js"></script>
```

#### Running the webpack compile during deploy

If you're using Capistrano, the easiest thing to do would be to add a custom `precompile_assets` task to compile the webpack assets after Sprocket's does its precompile:

``` ruby
namespace :assets do
  task :precompile_assets do
    run_locally do
      with rails_env: fetch(:stage) do
        execute 'rm -rf public/assets'
        execute :bundle, 'exec rake assets:precompile'
        execute :bundle, 'exec rake webpack:compile'
      end
    end
  end
end
```

In this case, I run these locally because I prefer to precompile locally and then rsync the assets up. You may want to adopt this strategy to avoid needing to install webpack and all its dependencies on your production web servers. It's also likely to be a lot faster - webpack production compiles can be somewhat slow if you have a *lot* of modules.

### Using webpack in development

It's easy to use the `development.config.js` we created during development. Simply call webpack like so:

    webpack --config config/webpack/development.config.js --watch --colors

This works well in conjunction with something like [foreman](https://github.com/ddollar/foreman) because you can then run Rails and webpack in the same console with `foreman start`, e.g.

    web: rails server -p $PORT
    webpack: webpack --config config/webpack/development.config.js --watch --colors

OK, I think that should just about do it. Hopefully this has helped you get started with webpack & Rails! Let me know if you have any questions :)
