import { chromium } from 'playwright'
const b = await chromium.launch()
const ctx = await b.newContext({ viewport:{width:1280,height:900} })
const p = await ctx.newPage()
const errs=[]
p.on('console', m=>{ if(m.type()==='error') errs.push('CONSOLE '+m.text().slice(0,200)) })
p.on('pageerror', e=>errs.push('PAGEERROR '+String(e).slice(0,300)))
await p.goto('http://127.0.0.1:8099/index.html', {waitUntil:'networkidle'})
// pick DWG
await p.setInputFiles('input[type=file]', 'samples/example_2018.dwg').catch(async()=>{
  console.log('no file input, listing buttons'); console.log(await p.locator('button').allTextContents())
})
await p.waitForTimeout(9000)
const status = await p.evaluate(()=>document.body.innerText.slice(0,300))
console.log('BODY:', status.replace(/\n+/g,' | '))
const canvases = await p.locator('canvas').count()
console.log('canvas count:', canvases)
await p.screenshot({path:'shots/ml-dwg.png'})
console.log('ERRORS:'); errs.slice(0,10).forEach(e=>console.log(' ', e))
await b.close()
