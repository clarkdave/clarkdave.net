---
title: "Twitter OAuth authorisation in a popup"
description: How to perform Twitter OAuth authorisation in a popup window, with examples for Rails and OmniAuth
created_at: 2012-10-30 07:59:48 +0100
kind: article
published: true
---

It's pretty common these days to let your users either sign up with or connect to Twitter from within your application. The typical way to do this is to redirect the user to Twitter, have them authorise and then bring them back.

Although this works fine, I wanted this to take place in a popup window, which avoids having the user leave your page and also means the whole thing can be handled in Javascript (invite the user to connect, wait for them to finish, and then act accordingly without a page refresh).

Facebook has a handy Javascript SDK for this situation and it works great. With Twitter, we need to do this manually, but even so it's not too difficult. I'll explain how to do this using the Ruby OmniAuth gem, but it'll be easy to adapt for other libraries.

<!-- more -->

### Overview

What makes this tick in 5 steps:

  1. User clicks 'Connect with Twitter' and you open a popup window to the Twitter OAuth URL
  2. User authorises the app and is redirected back to your server
  3. The page the user is redirected back to does `window.close()`
  4. Your original page checks periodically to see if the window has closed
  5. When it has closed, make a call to your server to verify if the user has now connected

If you just want to get started quickly, the TwitterConnect class below should be all you need to get going.

### The Javascript

We'll create a TwitterConnect class to keep all this tidy:

    #!javascript
    var TwitterConnect = (function() {

      // constructor accepts a url which should be your Twitter OAuth url
      function TwitterConnect(url) {
        this.url = url;
      }

      TwitterConnect.prototype.exec = function() {
        var self = this,
          params = 'location=0,status=0,width=800,height=600';

        this.twitter_window = window.open(this.url, 'twitterWindow', params);

        this.interval = window.setInterval((function() {
          if (self.twitter_window.closed) {
            window.clearInterval(self.interval);
            self.finish();
          }
        }), 1000);

        // the server will use this cookie to determine if the Twitter redirection
        // url should window.close() or not
        document.cookie = 'twitter_oauth_popup=1; path=/';
      }

      TwitterConnect.prototype.finish = function() {
        $.ajax({
          type: 'get',
          url: '/auth/check/twitter',
          dataType: 'json',
          success: function(response) {
            if (response.authed) {
              // the user authed on Twitter, so do something here
            } else {
              // the user probably just closed the window
            }
          }
        });
      };

      return TwitterConnect;
    })();

#### What's that cookie for?

Because I'm using Omniauth, by default it will always redirect to the same page (e.g. /auth/twitter/callback). We need that page to do a window.close(), however, if the user isn't using Javascript (and thus didn't get the popup) we'll want to do something different, like redirect them to another page.

So in setting this cookie, we can check for its existence in the final step of the OAuth process and if it's there, we'll render a simple page with a `window.close()`, and if not, we'll do something else.

If your own OAuth library makes it easy to give Twitter a different callback URL then you could skip the cookies and do that instead.

### Server-side: closing the popup

Assuming the user complets the app authentication with Twitter, they'll be returned to the OAuth callback URL. If this is happening in a popup, we need to ensure the resulting page runs `window.close()` or your user is going to get very confused. In your OmniAuth flow you can do something like this:

    #!ruby
    if omniauth['provider'] == 'twitter' and cookies[:twitter_oauth_popup]
      cookies[:twitter_oauth_popup] = nil
      # this session variable will be used later on, when we implement the check method
      session[:twitter_omniauth_success] = true
      return render 'twitter_popup_close', :layout => false
    end

This would be instead of a typical `redirect_to` (which might, say, send the user back to `request.env['omniauth.origin']` otherwise).

The actual page you need to render here can be as simple as this:

    #!html
    <!doctype html>
    <html>
    <body>
      <p>Close this window to continue</p>
      <script>window.close();</script>
    </body></html>

It's important to at least have some kind of message asking the user to close the window, just in case it doesn't auto close and they're left looking at a white screen. You could add some styles to make this look a bit friendlier in this edge case does happen.

#### What if the user clicks 'Cancel' on Twitter?

This is an important situation to handle -- if the user clicks Cancel they'll be sent back to the referring link... which is your original, non-popup page. Uh oh! It's going to look pretty weird if your user sees your site crammed inside this popup. I expect most users will probably just close the popup, but I wouldn't count on it.

A good way to solve this is to use that cookie we set earlier (the 'twitter_oauth_popup' one). In your controller - the one rendering the original page where users see the 'Connect with Twitter' button - check for the existence of this cookie and if you find it, render your `window.close()` view instead. For example:

    #!ruby
    class SessionsController < ApplicationController
      def new
        if cookies[:twitter_oauth_popup]
          cookies[:twitter_oauth_popup] = nil
          return render 'twitter_popup_close', :layout => false
        end
      end
    end

### Server-side: checking if the authorisation was successful

Take a look back at the Javascript: when the Twitter popup is closed, we run the `TwitterConnect.finish()` method. At this point all we know is that the window has closed - we have no idea if the user completed the authorisation or not. What we'll do is make an ajax call to our server to find out.

The actual mechanics of how you do this will depend on your framework and OAuth library. With Rails and OmniAuth, I have this route `get /auth/check/:provider' => 'authorisations#check'` where the check method is this:

    #!ruby
    def check
      if current_user and auth = current_user.authentications.where(:provider => 'twitter').first
        render :json => { :authed => true, :authentication => auth }
      elsif session[:twitter_omniauth_success]
        # we set this session variable earlier - it lets us determine if an authenticaiton
        # has been successful
        session[:twitter_omniauth] = nil
        render :json => { :authed => true }
      else
        render :json => { :authed => false }
      end
    end

In my case, I have three states this authorisation can be in:

  1. Authorised, complete and added to the current user
      * a new user account was just created and the user was logged in
      * an already logged-in user connected to Twitter
      * the user was already connected and they just logged in
  2. Authorised and in-progress (a new user has signed-up with Twitter - I need them to enter an email address)
  3. Not authorised (they probably closed the window)

Checking the first case is easy: by the time we make our ajax call, we've got a logged in user (either new or existing) with a Twitter authentication. The simplest thing to do here, in your TwitterConnect.finish() method, is a `window.refresh()`. You could also send the user information along from your `check` method above, and use that to populate user information on your page without requiring a page reload.

The second case requires a little extra work in our Omniauth flow and, potentially, on your client-side. A typical 'Sign up with Twitter' flow may at some point require you to ask the user for an email address.

### Handling a new Twitter sign up without a page reload

So let's assume the `check` method returns `{ :authed => true }`. The user authenticated your app with Twitter, but they're a new user and you need them to enter an email address (or anything else, like a password or username).

OmniAuth specific: make sure you're storing the OmniAuth info in the session, i.e. `session[:omniauth] = omniauth.except('extra')` so you can access it when you create the new user later.

If you intend on having the user enter a name or username, it might be helpful to get this information from Twitter. You can update your `check` method so in addition to `:authed => true` it also returns some of the user data from Twitter. If you're using OmniAuth this is as simple as `:omniauth => session[:omniauth]`. You'll then be able to pre-populate values in your form from this hash (e.g. Twitter username, or first name, both of which are provided by Twitter).

Now you need to show your user the form and listen for when it's submitted. When the users submits, you'll want to send a request to your server to create a new user. If you're using [Backbone.js](http://backbonejs.org) this could be as simple as:

    #!javascript
    var user = new User({ email: $('#user_email') });
    user.save({}, {
      success: function(model, response) {
        // the server just created this user! Now you can either do
        // a straight-forward `window.location.reload()`, or use the
        // model and response.user to update the user information on the page
      },
      error: function(model, response) {
        // either the User model validations failed, or the server
        // failed it (perhaps the email address is in use), we can
        // look at response.errors for this
      }
    });

You could also do this with plain ajax, or another framework of your choice. As for what the server-side part of this looks like, it'll be the same POST target that users would normally submit to if this was a traditional sign-up, such as:

    #!ruby
    class RegistrationsController < ApplicationController
      def create
        @user = User.new params[:user]

        # add_authentication is a convenience method on the User model to
        # create a new authentication for this user based on the omniauth session
        @user.add_authentication(sessions[:omniauth])

        respond_to do |format|
          format.html {
            if user.save
              sign_in_and_redirect(user)
            else
              render :new
            end
          }
          format.json {
            if user.save
              render :json => { :user => user }
            else
              render :json => { :errors => user.errors.full_messages }, :status => 422
            end
          }
        end
      end
    end

Obviously the above is a naive implementation of a user registration. I'd recommend using [Devise](https://github.com/plataformatec/devise) instead, and feel free to comment if you need any assistance hooking up any of the above with Devise.

### Finishing up

With the `TwitterConnect` class in place and all your server-side logic complete, the final step is to actually put this in action:

    #!javascript
    var twitter_btn = $('#twitter-connect-button');

    var twitter_connect = new TwitterConnect(twitter_btn.attr('href'));

    twitter_btn.on('click', function(e) {
      e.preventDefault();
      twitter_connect.exec();
    });

  And we're done! Let me know if you have any questions.
