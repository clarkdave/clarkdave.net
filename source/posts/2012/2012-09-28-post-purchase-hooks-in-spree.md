---
title: "Post-purchase hooks in Spree"
slug: post-purchase-hooks-in-spree
description: "A quick reference on how to add a post-purchase hook to Spree (v1.2.0)"
date: 2012-09-28 07:17:16 +0200
kind: article
published: true
---

[Spree](http://spreecommerce.com/) is a nifty e-commerce platform on Rails. It's open-source and fairly easy to customise. In particular, the ordering process uses [state_machine](https://github.com/pluginaweek/state_machine) which lets you hook in to any part you need to. I'm using Spree v1.2.0, which is the latest version right now.

Adding a post-purchase hook is easy. First you'll need to have the following in a file in your `lib/` folder. I just used `lib/spree_site.rb`:

``` ruby
Dir.glob(File.join(File.dirname(__FILE__), "../app/**/*_decorator*.rb")) do |c|
  Rails.configuration.cache_classes ? require(c) : load(c)
end
```

This tells Spree to look for files named _decorator in your `app/` directory and load them in.

Next up we want to override the Order model. Create the file `app/models/spree/order_decorator.rb` and stick this in:

``` ruby
Spree::Order.class_eval do

  def say_hello
    puts 'Hello!'
    puts "This order cost #{total}"
    # do something interesting, like notify an external webservice about this order
  end
end

Spree::Order.state_machine.after_transition :to => :complete,
                                            :do => :say_hello
```

The first part uses Ruby's class_eval to add a new method to the *Order* model. The second part tells the state machine to run the new 'say_hello' method after the :complete (end of checkout) transition occurs.

And that's all there is to it!