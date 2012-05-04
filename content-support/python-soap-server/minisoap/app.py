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

class MessageService(ServiceBase):
    @srpc(String, Integer, _returns=Iterable(String))
    def send_message(msg):
        yield 'Your message: %s' % msg

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