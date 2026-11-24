import { webkit } from 'playwright'
const b = await webkit.launch()
// iPhone-ish viewport, WebKit = Safari engine
const devices = [
  { name:'ml-2018', url:'http://127.0.0.1:8099/index.html', file:'samples/example_2018.dwg', wait:20000 },
  { name:'ff-2018', url:'http://127.0.0.1:8098/index.html?file=/example_2018.dwg', file:null, wait:20000 },
]
for (const d of devices) {
  const ctx = await b.newContext({ viewport:{width:390,height:844}, deviceScaleFactor:2, isMobile:true, hasTouch:true })
  const p = await ctx.newPage()
  const errs=[]
  p.on('console',m=>{if(m.type()==='error')errs.push(m.text().slice(0,160))})
  p.on('pageerror',e=>errs.push('PAGEERR '+String(e).slice(0,160)))
  await p.goto(d.url,{waitUntil:'load'})
  if (d.file) { await p.waitForTimeout(4000); await p.setInputFiles('input[type=file]', d.file).catch(e=>errs.push('input:'+e.message.slice(0,80))) }
  await p.waitForTimeout(d.wait)
  await p.screenshot({path:`shots/webkit-${d.name}.png`})
  console.log(d.name, 'errs:', errs.length, errs.slice(0,3))
  await ctx.close()
}
await b.close()
