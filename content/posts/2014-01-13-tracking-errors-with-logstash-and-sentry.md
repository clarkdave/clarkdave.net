---
title: "Tracking errors with Logstash and Sentry"
created_at: 2014-01-13 14:23:10 +0000
kind: article
published: true
---

[Logstash](http://logstash.net/) is an excellent way to eat up logs and send them elsewhere. In a typical setup you'll send them to Elasticsearch and the excellent Kibana for viewing and analysis, which works well but is missing a vital part: being alerted when your application throws errors.

There's a whole bunch of ways you can deal with errors without Logstash, one of which is [Sentry](https://getsentry.com/). This is a software service which takes your errors, samples and groups them and, crucially, alerts you by email (or many other options). Sentry can plug in to most applications with its different Raven clients, which will allow you to track errors as part of your application and then send them to Sentry directly.

But, well, if you're already using Logstash to log everything (including errors), wouldn't it be great to just have Logstash send errors on to Sentry for you? I think so! And, luckily, it's quick and easy to do!

<!-- more -->

### Introduction

Logstash comes bundled with a lot of outputs, but alas a Sentry-compatible Raven output is not one. Sentry doesn't have a public REST API, but all Raven clients send a message by HTTP anyway and so we can make a small Logstash output plugin to do this for us.

Note: Logstash does have a generic HTTP output, but because the Sentry HTTP endpoints expect a very specific body, I decided it would be easier to use a custom plugin than try to wrangle the HTTP output to do what we need.

### The Sentry plugin

Start by creating a new plugin in your Logstash plugins directly, like below. I don't know why the plugins directly also needs to have a `logstash` folder, but it does.

    /opt/logstash/server/plugins/logstash/outputs/sentry.rb

Now add this code to start the plugin - we'll implement the `receive` method in a moment.

    #!ruby
    require 'logstash/outputs/base'
    require 'logstash/namespace'

    class LogStash::Outputs::Sentry < LogStash::Outputs::Base

      config_name 'sentry'
      milestone 1

      config :key, :validate => :string, :required => true
      config :secret, :validate => :string, :required => true
      config :project_id, :validate => :string, :required => true

      public
      def register
        require 'net/https'
        require 'uri'
        
        @url = "https://app.getsentry.com/api/#{project_id}/store/"
        @uri = URI.parse(@url)
        @client = Net::HTTP.new(@uri.host, @uri.port)
        @client.use_ssl = true
        @client.verify_mode = OpenSSL::SSL::VERIFY_NONE

        @logger.debug("Client", :client => @client.inspect)
      end
    end

This initialises a plugin named `sentry` with three configuration values: `key`, `secret` and `project_id`. These can all be found in the `DSN` provided to you by Sentry for your project. You can find this DSN in Sentry, under project settings and `All Platforms`. It'll look something like this:

    https://0507f05a5d7f41aaaadba4fe669449fb:b69e48719e6541aaaa1301c8946502be@app.getsentry.com/371923

The values are:

    https://{key}:{secret}@app.getsentry.com/{project_id}

You might already be thinking "but Raven clients should use a DSN, not be hardcoded to use Sentry's domain" and you'd be right. It would be fairly trivial to change this plugin to act as a more generic Raven client. When I had more time I'd like to do just that, and submit to Logstash as a bundled output. This would then work not just for Sentry's hosted service but your own Sentry installations (Sentry is open-source too!)

Anyway, now let's implement `recieve` method which will actually send the message to Sentry:

    #!ruby
    public
    def receive(event)
      return unless output?(event)

      require 'securerandom'

      packet = {
        :event_id => SecureRandom.uuid.gsub('-', ''),
        :timestamp => event['@timestamp'],
        :message => event['message']
      }

      packet[:level] = event['[fields][level]']

      packet[:platform] = 'logstash'
      packet[:server_name] = event['host']
      packet[:extra] = event['fields'].to_hash

      @logger.debug("Sentry packet", :sentry_packet => packet)

      auth_header = "Sentry sentry_version=5," +
        "sentry_client=raven_logstash/1.0," +
        "sentry_timestamp=#{event['@timestamp'].to_i}," +
        "sentry_key=#{@key}," +
        "sentry_secret=#{@secret}"

      request = Net::HTTP::Post.new(@uri.path)

      begin
        request.body = packet.to_json
        request.add_field('X-Sentry-Auth', auth_header)

        response = @client.request(request)

        @logger.info("Sentry response", :request => request.inspect, :response => response.inspect)

        raise unless response.code == '200'
      rescue Exception => e
        @logger.warn("Unhandled exception", :request => request.inspect, :response => response.inspect, :exception => e.inspect)
      end
    end

You might need to tweak this code to suit your own logs. I filter all my logs so that they have a `fields` key which contains any contextual fields like user_id, response time, etc. It's useful to have this when examining errors, so I send off everything in `fields` to Sentry under its `extra` field.

This code also assumes that you have a value for each log in [fields][level], which is the log level. This is required for Sentry to know what kind of error it is. This can be a string like "warning", "error" or an numeric value.

**If you do use numeric log levels** an important caveat applies: your log level numbering scheme may not match that which Sentry uses.

Sentry will accept numeric log levels, but it treats them like so:

* 30: warning
* 40: error
* 50: fatal

If you have a different scheme, like I did, you'll need to adjust your numeric log level before sending it on to Sentry. In my case, all my log levels are +10, so 40 is actually a warning. This is an easy fix:

    #!ruby
    packet[:level] -= 10 if packet[:level] > 10

Finally, you may want to check the code for things like `event['host']` in case these you have these named differently.

### Adding the plugin to your Logstash config

With the plugin in place the only thing left to do is add it to your config as an output. Although you could just stick it in, this would result in *all* logs being sent to Sentry, a use case it's not really designed for (it excels when you only send it errors).

I recommend adding the Sentry output in combination with a condition so it's only used if the log is a warning or above (you could change this to errors or above if you don't need warnings in Sentry). This will look something like this:

    # if you use numeric log levels

    if [fields][level] >= 40 {
      sentry {
        'key' => 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
        'secret' => 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
        'project_id' => '137235'
      }
    }

    # if you use string log levels

    if [fields][level] == 'warning' or [fields][level] == 'error' or [fields][level] == 'fatal' {
      sentry {
        'key' => 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
        'secret' => 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
        'project_id' => '137235'
      }
    }

And that should be about it! Make sure you are passing the `--pluginpath` option to the Logstash server daemon so it can find your plugin, and don't forget you can also pass `-vv` for extra logging to help debug things if it doesn't work.