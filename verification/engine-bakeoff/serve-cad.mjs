// Mimics the iOS WKURLSchemeHandler: serves the built viewer and answers /__dwg__.
import http from 'node:http'
import fs from 'node:fs'
import path from 'node:path'
const root = path.resolve('ios/web/dist')
const dwgPath = process.argv[2]
const port = Number(process.argv[3] || 8097)
const types = {'.html':'text/html','.js':'text/javascript','.css':'text/css','.wasm':'application/wasm','.json':'application/json','.svg':'image/svg+xml'}
http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split('?')[0])
  if (url.endsWith('/__dwg__')) {
    res.writeHead(200, {'Content-Type':'application/octet-stream','Cache-Control':'no-store'})
    fs.createReadStream(dwgPath).pipe(res)
    return
  }
  let file = path.join(root, url)
  if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, 'index.html')
  if (!fs.existsSync(file)) { res.writeHead(404); res.end('404 '+url); return }
  res.writeHead(200, {'Content-Type': types[path.extname(file)] || 'application/octet-stream'})
  fs.createReadStream(file).pipe(res)
}).listen(port, () => console.log('cad viewer on', port, 'serving', dwgPath))
