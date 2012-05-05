---
title: "Building a static blog with nanoc"
description: A comprehensive guide to building a static blog using nanoc and Ruby
created_at: 2012-02-14 11:14:04 +0000
kind: article
published: true
---

Having a static site may feel a bit like a throwback, but the benefits are well noted and there are various frameworks around to turn your text and templates into HTML. For my site, I opted for [nanoc](http://nanoc.stoneship.org/), which is Ruby based and extremely flexible.

nanoc is simple to set up and use, but because it's so generic it doesn't (by default) do the things you might expect from a blog, like tags, archives, timestamps and the like. For something a bit more 'out the box', I'd suggest looking at [Jekyll](http://jekyllrb.com/), or [Octopress](http://octopress.org/) (which is even more feature-packed).

I wanted to use nanoc as it doesn't restrict your choice of template/rendering engine, and because it's lightweight and gets out of the way, making it easy to hammer into shape. In this post I'll explain how to flex nanoc into a simple blogging platform.

<!-- more -->

### Getting started

You'll need Ruby, Rubygems and nanoc. [The nanoc website](http://nanoc.stoneship.org/docs/2-installation/) explains how to get these but if you're already set up with Ruby/Rubygems, you can just do a `gem install nanoc` to grab the latest version. This post is written with nanoc *3.2.4* so there may be minor differences if you're using a newer version.

Once you've got nanoc installed, fire up a terminal and type

	nanoc create_site myblog

If all went well, you should now have a blank nanoc site in the `myblog` folder.

### A nanoc primer

Once you're inside the `myblog` directory, you can type

	nanoc compile

This will create a new directory called `output` and drop an index.html and style.css file inside it. This is your compiled site - what you'll stick on your web server and serve up.

When nanoc compiles your site, it looks in your `content` directory for files and processes them based on rules you provide. The rules we care about for now are:

* **compile** rules, which tell nanoc *how* to compile a file. So, if you've written your posts using Markdown, you'll have a rule telling nanoc to run these through a Markdown parser that outputs HTML.
* **route** rules, which tell nanoc *where* to put the compiled file in the `output` directory. By default, nanoc will just place files according to their position inside the `content` directory, but if you want to place certain files somewhere else (like putting blog posts in a directory like /2012/02/post-title/) you can do it with these rules.

These rules are written in Ruby, and have access to all the information about the current item that is being processed. This gives them a lot of flexibility and makes it easy to compile and route items how you want.

### Building that blog

Every blog needs a layout. This is the surrounding template that you see on every page. From your `myblog` directory open up the file `layouts/default.html`. You should see the default layout provided by nanoc. Throw that away and put this in instead:

	#!rhtml
	<!DOCTYPE HTML>
	<html lang="en">
	  <head>
	    <meta charset="utf-8">
	    <title>My blog - <%= @item[:title] %></title>
	    <link rel="stylesheet" type="text/css" 
	      href="http://twitter.github.com/bootstrap/assets/css/bootstrap.css" 
	      media="screen">
	    <link rel="stylesheet" type="text/css" href="/style.css">
	  </head>
	  <body>
	    <div class='navbar'>
	      <div class='navbar-inner'>
	        <div class='container'>
	          <a class='brand' href='/'>My Blog</a>
	          <ul class='nav'>
	            <li class='active'><a href='/'>Home</a></li>
	            <li><a href='/about'>About</a></li>
	          </ul>
	        </div>
	      </div>
	    </div>
	    <section class='content'>
	      <%= yield %>
	    </section>
	  </body>
	</html>

Now open up the file `content/stylesheet.css`, throw away what's there and put this in:

	#!css
	.content {
	  width: 800px;
	  background: #f5f5f5;
	  border: 1px solid #ddd;
	  border-top: none;
	  margin: 0 auto;
	  padding: 60px 20px 0 60px;
	}
	.post aside {
	  color: #888;
	  padding-bottom: 8px;
	  border-bottom: 1px solid #aaa;
	}
	.post article {
	  margin: 10px 0 60px 0;
	}

Now recompile with

	nanoc compile

and nanoc should report that it updated `output/index.html` and `output/style.css`. As part of the compilation rules, you can tell nanoc to apply particular layouts to the items it compiles. By default, nanoc is applying the *'default'* layout to everything and, because we just modified the *default* layout, nanoc decided it had to recompile `content/index.html`.

#### Viewing the output

Right now, you should have a few files in the `output/` directory. If you were to copy this directory to a webserver and view it, you'd see your site it stands. nanoc, however, does provide an easier way to view your site during development. First install the adsf gem, which nanoc uses for its webserver preview:

	gem install adsf

and then type

	nanoc view

Once you've done that, you should be able to visit http://localhost:3000 in your browser and see your basic site for the first time. 

#### Automatic compilation

If you get tired of typing `nanoc compile`, type `nanoc watch` instead. This will automatically compile your site when it detects any changes.

### Back to that blog, then...

We've now got a basic website, but it's not a blog yet. We need posts, and also a way to show recent posts on the index page. Fortunately, nanoc has a built-in helper to make this easier.

Helpers are little plugins that extend nanoc. There are a few provided by default, and it's also easy to write your own (which we'll do later). For now, open up the file `lib/default.rb` and paste in the following:

	#!ruby
	include Nanoc3::Helpers::Blogging
	include Nanoc3::Helpers::Tagging
	include Nanoc3::Helpers::Rendering
	include Nanoc3::Helpers::LinkTo

* The *Blogging* helper extends nanoc content items with a few fields such as *title* and *created_at*, and also provides some helper methods to our layouts we can use to list posts.
* The *Tagging* helper lets us add tags to content items and query them.
* The *Rendering* helper lets us use *view partials*, which allows us to nest layouts (this'll let us built sub-layouts for posts)
* The *LinkTo* helper lets us construct URLs for other items (we'll use this in our index item to link to multiple posts)

### Making a post

Create a new directory, `content/posts` and in it create a new file called `2012-02-10-my-first-post.md`. Paste the following into this file:

	#!yaml
	---
	title: "My first post"
	created_at: 2012-02-10 09:00:00 +0000
	kind: article
	---

	Welcome to my blog. It is filled with wondrous, bloggy things. Cats, mostly.

The bit at the top of this file, inside the `---`, is the metadata for this piece of content. When nanoc compiles this item it'll look for this metadata and make it available to our rules and layouts.

The `kind: article` is required for the aforementioned Blogging helper to determine which content items are considered posts.

If you were to compile and view the site now, you'd be able to see this post at the URL `/posts/2012-02-10-my-first-post/`, but we're going to set up a *routing* rule to place this in a more semantic location.

Open up the file `Rules` in the root of `myblog`. The rules in this file are evaluated sequentially for each item in your `content` directory, and the first one that matches will be executed. The last compile rule you should have in this file matches on a wildcard, which means if no other compile rules match, this one will be used. The same goes for the route rules.

Go ahead and add a new *route* rule, but place it above the `route '*' do ...` line

	#!ruby
	route '/posts/*' do
	  y,m,d,slug = /([0-9]+)\-([0-9]+)\-([0-9]+)\-([^\/]+)/
	    .match(item.identifier).captures

	  "/#{y}/#{m}/#{slug}/index.html"
	end

As mentioned earlier, each rule has access to the item that's currently being processed via the `item` variable. `item.identifier` provides the filename (sans extension). In our rule above we're doing a quick regular expression search on the identifier in order to get the publication date (year-month-day) and the slug (a URL-safe version of the post title).

Once we've got these, we're returning a string built with the values. This will give a string resembling something like "/2012/02/my-first-post/index.html".

Recompile and you should find a new file has been created: `/output/2012/02/my-first-post/index.html`. nanoc has placed the post we just created in a different location, per our new routing rule.

### Formatting blog posts with Markdown

[Markdown](http://daringfireball.net/projects/markdown/basics) is a great formatter for writing blog posts. It'll automatically create paragraphs and has a simple (but exhaustive) syntax for doing all sorts of things like headers and lists. nanoc makes it easy to run our posts through a Markdown parser.

To start with, install the `kramdown` gem, which is a Ruby Markdown engine.

	gem install kramdown

Now open up the `Rules` file again, and add a new `compile` rule just above the `compile '*' do` line:

	#!ruby
	compile '/posts/*' do
	  filter :kramdown
	  layout 'default'
	end

Any items nanoc finds in `content/posts/` will hit this rule, and will have the kramdown filter applied on their content. Filters in nanoc transform the content of an item - there are quite a few built-in, supporting popular Ruby gems, and you can write your own easily if you need to.

Now, so we can check if it works, edit the blog post from before and change the content to this (make sure to leave the metadata in place):

	Welcome to my blog!

	It is filled with wondrous, bloggy things. Cats, mostly.

	## Where are the cats?

	They've all wandered off. *Has anyone seen my cats?!*

Recompile and open the file `output/2012/02/my-first-post/index.html`. Inside the `<section>` tag you should see the content, post-Markdown filter. It should look something like this:

	#!html
	<p>Welcome to my blog!</p>
	<p>It is filled with wondrous, bloggy things. Cats, mostly.</p>
	<h1 id="where-are-the-cats">Where are the cats?</h1>
	<p>They’ve all wandered off. <em>Has anyone seen my cats?!</em></p>

Markdown has automatically created paragraphs, and turned `## ...` into a header. You can find a guide to all of Markdown's syntax at [Daring Fireball](http://daringfireball.net/projects/markdown/syntax). Although we're using Markdown for this example, you don't have to. You could use a different filter like Textile, or just use straight HTML instead.

### Creating a layout for blog posts

Right now, we've got a single layout for all our content items, `default.html`. Let's build a *post* template that's more suitable for displaying an individual blog post.

Create a new file `layouts/post.html` and in it put:

	#!rhtml
	<% render 'default' do %>
	  <div class='post'>
	    <h1><%= item[:title] %></h1>
	    <aside>Posted at: <%= item[:created_at] %></aside>
	    <article>
	      <%= yield %>
	    </article>
	  </div>
	<% end %>

This is using the *Rendering* helper we included earlier, and is rendering the `default` layout but passing in additional content (the markup for a blog post).

Next, open up `Rules` again and change our compile rule for posts so it looks like this:

	#!ruby
	compile '/posts/*' do
	  filter :kramdown
	  layout 'post'
	end

Now when nanoc compiles a post, it will apply the *post* layout instead. This layout includes our main *default* layout in turn. If you wanted to have a completely different page for individual blog posts, you could skip the `<% render 'default' do %>` part of the post layout.

Recompile again and open up `output/2012/02/my-first-post/index.html`. This time, inside the `<section>` tag, you should see the blog post with the *post* layout applied to it, like this:

	#!html
	<div class='post'>
	  <h1>My first post</h1>
	  <aside>Posted at: 2012-02-10 09:00:00 +0000</aside>
	  <article>
	    <p>Welcome to my blog!</p>
	    <p>It is filled with wondrous, bloggy things. Cats, mostly.</p>
	    <h1 id="where-are-the-cats">Where are the cats?</h1>
	    <p>They’ve all wandered off. <em>Has anyone seen my cats?!</em></p>
	  </article>
	</div>

### Listing recent posts on the index page

A common blog trope, we're now going to update our blog's index page to display recent blog posts. The *Blogging* helper we included earlier has a couple of handy functions we can use do do this easily. Open up `content/index.html` and delete the HTML that's already in there (leave the metadata intact) and add this:

	#!rhtml
	<% sorted_articles.each do |post| %>
	  <div class='post'>
	    <h1><%= link_to post[:title], post.path %></h1>
	    <aside>Posted at: <%= post[:created_at] %></aside>
	    <article>
	      <%= post.compiled_content %>
	    </article>
	  </div>
	<% end %>

`sorted_articles` is a variable provided by the *Blogging* helper which contains an ordered list (most recent first) of every item of content which has a `kind: article` in its metadata. With that, we're using ERB (the Ruby templating language) to iterate through each item and create some markup for each one. We use the `link_to` helper to generate a link to the full post, and we're printing out `post.compiled_content`, which is the final state of the post's content (after filters have been applied).

To see this in action, go ahead and add another post: `content/posts/2012-02-12-help-have-you-seen-my-cats.md`

	#!yaml
	---
	title: "Help! Have you seen my cats?"
	created_at: 2012-02-12 09:00:00 +0000
	kind: article
	---

	My cats appear to have taken leave of me. Have you seen them?

Now recompile, run `nanoc view` and view your site at [http://localhost:3000](http://localhost:3000). You should see a list with your two posts and, when you click a title, you should be taken to the individual post page.

### Further refinements

You should now have a basic but robust blogging framework set up, but there are a few more things we can do to improve it.

#### Put a human readable date on blog posts

We're just showing the default created_at timestamp at the moment, which isn't too nice to look at. We can improve this by writing a nanoc *helper*. Open up the file `lib/default.rb` and add this at the bottom:

	#!ruby
	module PostHelper
	  def get_pretty_date(post)
	    attribute_to_time(post[:created_at]).strftime('%B %-d, %Y')
	  end
	end

	include PostHelper

This helper will now be available to our layouts. It has a single method which gets the *created_at* attribute from the post's metadata and then outputs a formatted date string. Now open up the `layouts/post.html` and update the date output so it looks like this:

	#!rhtml
	<aside>Posted at: <%= get_pretty_date(item) %></aside>

You may also want to make the same change to your `content/index.html` file for consistency.

#### Display only the first part of a post on the index page (a 'fold')

This is easily done with another helper method. Decide on a 'break delimiter' - something you can place in your post's content to indicate where you'd like the split to occur. In these examples we'll use `<!-- more -->`. This choice (a HTML comment) is convenient as the Markdown processor will ignore it and won't attempt to turn it into a paragraph.

Start by updating the content in one of your existing posts. Stick in some filler text like this:

	Lorem ipsum dolor sit amet, consectetur adipiscing elit. Donec a pharetra justo. 
	Ut lacinia, nulla vitae auctor consectetur, urna ipsum euismod mauris.

	<!-- more -->

	Aliquam vehicula, odio tempus dapibus hendrerit, magna lorem vestibulum felis. 
	Donec neque nulla, imperdiet ut bibendum vitae, rutrum vitae urna. 
	Phasellus libero felis, facilisis eget sagittis at, scelerisque vel turpis.

The idea is that only text above the `<!-- more -->` will show up on the index page. Everything else will only be visible on the post's own page. Open up `lib/default.rb` and add a new method to the `PostHelper` we created earlier:

	#!ruby
	def get_post_start(post)
	  content = post.compiled_content
	  if content =~ /\s<!-- more -->\s/
	    content = content.partition('<!-- more -->').first +
	    "<div class='read-more'><a href='#{post.path}'>Continue reading &rsaquo;</a></div>"
	  end
	  return content
	end

This method examines the compiled content for a given post and checks if it contains `<!-- more -->`. If it does, it partitions the content into two parts (above and below the fold), and throws the below part away. It then adds an extra 'Continue reading' link at the end of the content which links to the location of the post.

One last thing we need to do is update `content/index.html` to use this new helper:

	#!rhtml
	<article>
	  <%= get_post_start(post) %>
	</article>

Now if you compile and view your blog's index page, you should see only the content above the `<!-- more -->` comment, and there should be a link to continue reading.

#### Write a Rake task to assist in creating new blog posts

As we have it now, it's a bit of a pain to create a new blog post. You need to manually create the file, ensure the date is correct, and then enter the meta data by hand. I use a simple Rake task to automate this process.

Open up `Rakefile` in your blog's root, and paste the following task at the bottom:

	#!ruby
	require 'stringex'
	desc "Create a new post"
	task :new_post, :title do |t, args|
	  mkdir_p './content/posts'
	  args.with_defaults(:title => 'New Post')
	  title = args.title
	  filename = "./content/posts/#{Time.now.strftime('%Y-%m-%d')}-#{title.to_url}.md"

	  if File.exist?(filename)
	    abort('rake aborted!') if ask("#{filename} already exists. Want to overwrite?", ['y','n']) == 'n'
	  end

	  puts "Creating new post: #{filename}"
	  open(filename, 'w') do |post|
	    post.puts '---'
	    post.puts "title: \"#{title}\""
	    post.puts "created_at: #{Time.now}"
	    post.puts 'kind: article'
	    post.puts 'published: false'
	    post.puts "---\n\n"
	  end
	end

This uses the stringex gem to do the conversion of title to slug, so you'll need to do a `gem install stringex` before using this task. After you've saved the file, you can create new posts like this:

	#!sh
	rake new_post["It's OK everyone! I found my cats"]

This will create the file `content/posts/2012-02-14-its-ok-everyone-i-found-my-cats.md` and pre-populate the meta data with a title and a date.

### Where to go from here?

This is, hopefully, enough to get you started. The finished sample blog from this guide is [available on GitHub](https://github.com/clarkdave/nanoc-blog-example), and you can also check out the [clarkdave.net source](https://github.com/clarkdave/clarkdave.net) for further reference.

I do plan on writing a sequel to this guide, which will cover a few more advanced topics such as setting up tagging, archive pages, syntax highlighting and deployment options.

Thanks for reading!