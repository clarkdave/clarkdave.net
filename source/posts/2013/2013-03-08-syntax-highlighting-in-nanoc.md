---
title: "Syntax highlighting in nanoc"
slug: syntax-highlighting-in-nanoc
description: Syntax highlighting in nanoc with Pygments and Markdown
date: 2013-03-08 16:48:55 +0100
kind: article
published: true
---

Syntax highlighting is easy in nanoc using the (built-in) `colorize_syntax` filter and [Pygments](https://pygments.org/). Pygments is an extremely robust Python library with support for many languages. You wouldn't ordinarily want to call out to a Python application from your Ruby app, but as your nanoc site is compiled this method works great.

<!-- more -->

### Install Pygments

The first thing you'll need to do is install Pygments. For Ubuntu, recent versions of OSX and many other systems, you can do:

    sudo easy_install Pygments

Once you've installed it, verify it's available by running `pygmentize` from a terminal. If it didn't work, the [Jekyll wiki has more detailed instructions for various operating systems](https://github.com/mojombo/jekyll/wiki/install).

### Install the pygments.rb gem

Because Pygments is a Python library, we need a way for Ruby to talk to it. Rather than do this by hand, there's an excellent gem called `pygments.rb` which will do this for you. It's pretty fast, so your compiles shouldn't suffer too much.

So, add `pygments.rb` to your Gemfile, or do:

    gem install pygments.rb

### Set up the colorize_syntax filter

nanoc comes with a `colorize_syntax` filter which knows how to speak pygments. So, in your `Rules` file add the following line in the `compile` block you want pygments to run with:

    #!ruby
    filter :colorize_syntax, :default_colorizer => :pygmentsrb

For example, with this blog, I run the colourize filter against all my posts, so my `compile` block is:

    #!ruby
    compile '/posts/*' do
      filter :kramdown
      filter :colorize_syntax, :default_colorizer => :pygmentsrb
      layout 'post'
    end

#### What if I don't use Markdown?

That's OK. The `colourize_filter` operates on anything within `<code>` tags. So if you're writing your content with plain HTML, stick your code examples within `<code>` tags for the filter to work:

    #!html
    <pre><code>#!ruby
    def meow
      puts 'Miauuu'
    end</code></pre>

### Styling the output

When Pygments is run on a code block, it'll tokenize everything into `<span>` tags with classes. To actually get the colour highlighting to work, you'll need some CSS. I actually couldn't find a nice collection of CSS for Pygments, but they are out there, and can be found [with some searching](https://www.google.com/search?q=pygments+css).

The styles I use for the syntax highlighting on this blog are in [this gist](https://gist.github.com/clarkdave/5117910).

### Highlight your codes!

With everything in place, you should now be able to write your Markdown as usual but prefix your code blocks with `#!language`, where `language` is one of the (many) [supported languages in Pygments](https://pygments.org/languages/).

If you find your development compiles (e.g. `nanoc watch`) are too slow now that you're highlighting your code, you may appreciate [this tip on speeding up nanoc compiles](https://clarkdave.net/2012/05/speeding-up-nanoc-compiles/).
