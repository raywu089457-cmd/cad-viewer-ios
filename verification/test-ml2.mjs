import { chromium } from 'playwright'
const files = ['samples/example_2000.dwg','samples/example_2013.dwg','samples/example_r12.dxf']
const b = await chromium.launch()
for (const f of files) {
  const ctx = await b.newContext({ viewport:{width:1000,height:700} })
  const p = await ctx.newPage()
  const errs=[]
  p.on('console', m=>{ if(m.type()==='error') errs.push(m.text().slice(0,180)) })
  p.on('pageerror', e=>errs.push('PAGEERR '+String(e).slice(0,180)))
  const t0=Date.now()
  await p.goto('http://127.0.0.1:8099/index.html',{waitUntil:'networkidle'})
  await p.setInputFiles('input[type=file]', f)
  await p.waitForTimeout(9000)
  const name=f.split('/').pop()
  // count non-black pixels as a render proxy
  const painted = await p.evaluate(()=>{
    const cs=[...document.querySelectorAll('canvas')]
    return cs.map(c=>{ try{ const g=c.getContext('2d')||c.getContext('webgl2'); return c.width+'x'+c.height }catch(e){return 'na'} })
  })
  await p.screenshot({path:`shots/ml-${name}.png`})
  console.log(name, '->', 'canvases', JSON.stringify(painted), 'errs', errs.length, errs.slice(0,3), ((Date.now()-t0)/1000).toFixed(1)+'s')
  await ctx.close()
}
await b.close()
