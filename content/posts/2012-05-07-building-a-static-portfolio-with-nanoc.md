---
title: "Building a static portfolio with nanoc"
description: A guide to building a static portfolio using nanoc and Ruby
created_at: 2012-05-07 19:11:50 +0100
kind: article
published: true
---

A few months I blogged about [building a static blog using nanoc](/2012/02/building-a-static-blog-with-nanoc/) and as I recently finished off my little site with a portfolio section, I figured I'd throw up a guide on how to do that (it's really easy!)

The principle is almost identical to how blog posts work in nanoc: each portfolio entry is its own file, which some kind of identifier for the nanoc parser to pick up. This is combined with a custom helper to pull out these entries and from there they can be displayed in whatever way makes sense.

I won't be as hands-on with this guide as I was with [the previous](/2012/02/building-a-static-blog-with-nanoc/), so if you feel lost give that one a read first.

<!-- more -->

### Getting started

We'll start by creating a single portfolio entry, so create a new folder inside your nanoc site's `content` directory - I call mine 'portfolio'. Inside here, create a new file for your first portfolio entry with a name like this:

    2011-09-11-something-awesome.md

As with blog posts, we'll use the date and slug portion of this filename to construct the final URL for this portfolio entry. Now we'll want some content:

    #!yaml
    ---
    title: Something Awesome
    url: http://example.com
    created_at: 2011-09-11
    kind: portfolio
    image_id: somethingawesome
    ---

    This is an awesome project I worked on last year. I can't talk too much about it.

The key field here is `kind: portfolio`. In our helper, we'll use this to figure out which content items we need. The other fields you use here are entirely up to you. I use the `image_id` field to work out the URL to a static image to use for the portfolio entry (which I'll cover in a moment).

### Creating the Portfolio helper

Now we've got a bit of static content, we need a Ruby helper to tell nanoc how to process it. Create the file `lib/portfolio.rb` and inside put this:

    #!ruby
    module PortfolioHelper

      def portfolios
        @items.select { |item| item[:kind] == 'portfolio' }
      end

      def sorted_portfolios
        portfolios.sort_by { |p| attribute_to_time(p[:created_at]) }.reverse
      end

      def portfolio_image_url(item, type)
        '/images/portfolio/' + item[:image_id] + '_' + type + '.jpg'
      end
    end

    include PortfolioHelper

This creates a new helper module and then includes it. Each of the methods inside the PortfolioHelper module will now be available to content items, layouts and other helpers.

The basic method here, `portfolios`, simply returns a list of nanoc items whose *kind* property is set to 'portfolio' - this is exactly how the built-in Blogging helper works too. We also have a `sorted_portfolios` helper method which orders the portfolio entries so that the newest is first.

Finally, we have the `portfolio_image_url` method. I use this to easily attach get the URL of a portfolio image in various states. For example, in my `content/images/portfolio` folder, I'd have:

    somethingawesome_full.jpg
    somethingawesome_small.jpg
    somethingawesome_large.jpg

This works for me - you might want to do something more robust (such as checking for the existance of the image, or looking for an image of that name with multiple file extensions and returning the first one found, instead of hardcoding the jpg extension). The nice thing about nanoc is you can make these lazy, unoptimised shortcuts because the slowness will only happen once, at compile time.

### Rendering the portfolio entries

With our helper in place, we now just need to implement it into our layout. There's two steps to this - one, you'll probably want some kind of index page for your portfolio, and two - the view for an individual portfolio entry.

Let's start with the portfolio index. Create a new content file in haml, erb or whatever markup engine you're using - e.g. `content/portfolio.haml` and in it iterate through the list returned by the `sorted_portfolios` helper and render each one. As a reference, here's a basic example of this in haml:

    #!haml
    %h2 My portfolio
    - sorted_portfolios.each do |entry|
      .portfolio-entry
        %h3= link_to entry[:title], entry
        .picture{:style => 'background-image:url(' + portfolio_image_url(entry, 'small') + ')'}

This would list the portfolio entries (with the newest first), with a linked title and 'small' version of the associated image.

Next, we'll want to tell nanoc how to render an individual portfolio (and also, how to route it). Open up your nanoc `Rules` file and add these rules:

    #!ruby
    compile '/portfolio/*' do
      filter :kramdown 
      layout 'portfolio'
    end

    route '/portfolio/*' do
      y,m,d,slug = /([0-9]+)\-([0-9]+)\-([0-9]+)\-([^\/]+)/.match(item.identifier).captures
      "/portfolio/#{y}/#{slug}/index.html"
    end

The compile rule tells nanoc to run the `kramdown` Markdown parser on our portfolio's content (everything that comes after the yaml metadata -- if you're not using that, you don't need to run the parser) and then sets it to use the 'portfolio' layout for rendering.

The routing rule deconstructs the portfolio entry's filename into date components and a slug, and then creates a URL of the form `/portfolio/2011/something-awesome/`. You can tweak this to match your own URL scheme.

Finally, we can create the portfolio layout, which will be in `/layouts/portfolio.haml` (or .erb, or something else, if you're not using haml). This can be treated in the same way as a blog post - you'll have a reference to the individual portfolio item and all of its attributes, and can layout the page however you like. A simple example could be:

    #!haml
    %h2= item[:title]
    .portfolio-full
      - if item[:url]
        .url= '<strong>URL:</strong> ' + item[:url]
      .picture{:style => 'background-image:url(' + portfolio_image_url(entry, 'full') + ')'}
      .details
        = yield

Don't forget, yield will simply output the 'content' of the portfolio entry (everything after the metadata), so if you don't have any content, you won't need the yield.

That should be it. As with anything in nanoc, it's trivial to expand your content items with any extra information. As an example, on my own portfolio items I have to additional bits of metadata:

    #!yaml
    snippet: A short summary of this project
    technologies: [ruby, rails, python, jquery]

I then use the snippet on the index page, and can simply iterate through the `item[:technologies]` list on the full portfolio page in the layout as a list of strings.

Thanks for reading.

#### Related posts

* [Building a static blog with nanoc](/2012/02/building-a-static-blog-with-nanoc/)