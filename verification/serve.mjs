import http from 'node:http'
import fs from 'node:fs'
import path from 'node:path'
const root = process.argv[2]
const port = Number(process.argv[3]||8099)
const types={'.html':'text/html','.js':'text/javascript','.mjs':'text/javascript','.css':'text/css','.wasm':'application/wasm','.json':'application/json','.dwg':'application/octet-stream','.dxf':'application/octet-stream','.svg':'image/svg+xml','.png':'image/png','.woff2':'font/woff2','.ttf':'font/ttf'}
http.createServer((req,res)=>{
  let p = decodeURIComponent(req.url.split('?')[0])
  let f = path.join(root, p)
  if (fs.existsSync(f) && fs.statSync(f).isDirectory()) f = path.join(f,'index.html')
  if (!fs.existsSync(f)) { res.writeHead(404); res.end('404 '+p); return }
  res.writeHead(200,{'Content-Type':types[path.extname(f)]||'application/octet-stream','Access-Control-Allow-Origin':'*'})
  fs.createReadStream(f).pipe(res)
}).listen(port, ()=>console.log('serving '+root+' on '+port))
