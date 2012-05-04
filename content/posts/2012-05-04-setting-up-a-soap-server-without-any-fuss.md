---
title: "Setting up a SOAP server without any fuss"
created_at: 2012-05-04 19:00:08 +0100
kind: article
published: false
---

I recently had the unfortunate task of setting up a basic SOAP server for the purposes of some cross-University communication. Java tends to be very good (or as good as you can be, dealing with SOAP) but it's still quite long-winded and, to save time, I also wanted something I could easily deploy to Heroku.

After spending a little while looking at some options, I settled on Python and [rpclib](https://github.com/arskom/rpclib). This let me create a SOAP server without any pain, and of course it was simple to deploy to Heroku as well. The biggest time-saver is that rpclib is not by necessity a contract-first SOAP server - so you don't need to write your own WSDL, but can simply write a service class in Python and have rpclib autogenerate the WSDL.

I can't imagine there's many people who'll need to know how to do this (a SOAP server sitting on Heroku? How common is that?) but I'm throwing it up here for future reference. Although if I ever have to work with SOAP again I may shoot myself.

<!-- more -->

### What to do

We'll create a new directory for our app:

    mkdir minisoap && cd minisoap

And then create a virtual environment and source it:

    virtualenv venv --distribute
    source venv/bin/activate

Now we can install rpclib and its dependencies:

    pip install rpclib

Finally, create *app.py* which will contain all our code. Here are all the imports you'll need:

    #!python
    import logging
    import os

    from rpclib.application import Application
    from rpclib.decorator import srpc
    from rpclib.interface.wsdl import Wsdl11
    from rpclib.protocol.soap import Soap11
    from rpclib.service import ServiceBase
    from rpclib.model.complex import Iterable
    from rpclib.model.primitive import Integer
    from rpclib.model.primitive import String
    from rpclib.server.wsgi import WsgiApplication

And next, our service:

    #!python
    class MessageService(ServiceBase):
      @srpc(String, Integer, _returns=Iterable(String))
      def send_message(msg):
        yield 'Your message: %s' % msg

And finally, a chunk of boilerplate to configure rpclib, tell it to use the service we just created and then serve forever as a wsgi application.

    #!python
    if __name__=='__main__':
      try:
          from wsgiref.simple_server import make_server
      except ImportError:
          print "Error: server requires Python >= 2.5"

      logging.basicConfig(level=logging.INFO)
      logging.getLogger('rpclib.protocol.xml').setLevel(logging.DEBUG)

      application = Application([MessageService], 'org.temporary.soap',
                  interface=Wsdl11(), in_protocol=Soap11(), out_protocol=Soap11())

      port = int(os.environ.get('PORT', 5000))

      server = make_server('0.0.0.0', port, WsgiApplication(application))

      print "listening to http://0.0.0.0:%s" % port
      print "wsdl is at: http://0.0.0.0:%s/?wsdl" % port

      server.serve_forever()

From here you should be able to run `python app.py` and then you can hit http://localhost:5000/?wsdl to view your glorious WSDL.

### Deplying to Heroku

It's easy to get this on Heroku. Do a `pip freeze` to get the requirements.txt:

    pip freeze > requirements.txt

And then create the file `Procfile` and stick this inside:

    web: python app.py

From here, it's as straightforward as any other Heroku Cedar deployment. Stick it in a git repository and then push it up to Heroku. Enjoy!