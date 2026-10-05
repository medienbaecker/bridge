# A throwaway https server with a self-signed certificate, for the trust case.
import http.server, ssl, sys, os
port, cert, key, root = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
os.chdir(root)
srv = http.server.HTTPServer(('0.0.0.0', port), http.server.SimpleHTTPRequestHandler)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(cert, key)
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
srv.serve_forever()
