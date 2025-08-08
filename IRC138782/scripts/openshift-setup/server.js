const http = require('http');
const port = process.env.APP_PORT || 8080;
const server = http.createServer((req, res) => {
  res.writeHead(200, {'content-type': 'text/plain'});
  res.end('Hello from OpenShift on Podman!\n');
});
server.listen(port, () => console.log('Server listening on', port));
