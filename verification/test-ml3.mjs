import { chromium } from 'playwright'
const b=await chromium.launch()
const ctx=await b.newContext({viewport:{width:1000,height:700}})
const p=await ctx.newPage()
const errs=[]
p.on('console',m=>{if(m.type()==='error')errs.push(m.text().slice(0,150))})
await p.goto('http://127.0.0.1:8099/index.html',{waitUntil:'networkidle'})
await p.setInputFiles('input[type=file]','ml-example/dist/example_2018.dxf')
await p.waitForTimeout(9000)
await p.screenshot({path:'shots/ml-libredwg-converted-dxf.png'})
console.log('errs',errs.slice(0,3))
await b.close()
