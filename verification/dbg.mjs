import { chromium } from 'playwright'
const b=await chromium.launch(); const p=await b.newPage({viewport:{width:1000,height:900}})
await p.goto(process.argv[2]); await p.waitForTimeout(500)
const info = await p.evaluate(()=>{
  const svg=document.querySelector('svg')
  const lines=svg.querySelectorAll('line')
  const first=lines[0]
  const bb = first? first.getBBox(): null
  const svgbb = svg.getBBox()
  return {lines:lines.length, svgbb:{x:svgbb.x,y:svgbb.y,w:svgbb.width,h:svgbb.height},
    viewBox: svg.getAttribute('viewBox'),
    firstLine: first? first.outerHTML.slice(0,200):null,
    computed: first? (()=>{const cs=getComputedStyle(first);return {stroke:cs.stroke,w:cs.strokeWidth,ve:cs.vectorEffect}})():null}
})
console.log(JSON.stringify(info,null,1))
await b.close()
