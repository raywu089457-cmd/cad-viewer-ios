import { chromium } from 'playwright'
const files=['example_2018.dwg','example_2000.dwg','example_r12.dxf']
const b=await chromium.launch()
for(const f of files){
  const ctx=await b.newContext({viewport:{width:1100,height:780}})
  const p=await ctx.newPage()
  const log=[]
  p.on('console',m=>{const t=m.text(); if(/DIAG|EVENT|error|Error/.test(t)) log.push(m.type()+': '+t.slice(0,200))})
  p.on('pageerror',e=>log.push('PAGEERR '+String(e).slice(0,200)))
  await p.goto(`http://127.0.0.1:8098/index.html?file=/${f}`,{waitUntil:'networkidle'})
  await p.waitForTimeout(12000)
  await p.screenshot({path:`shots/ff-${f}.png`})
  console.log('===',f,'===');
  log.slice(0,8).forEach(l=>console.log('  ',l))
  const txt=await p.evaluate(()=>document.body.innerText.replace(/\n+/g,' | ').slice(0,300))
  console.log('  BODY:',txt)
  await ctx.close()
}
await b.close()
