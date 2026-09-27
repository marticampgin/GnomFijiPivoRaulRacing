'use strict';
const assert = require('node:assert/strict');
const {chromium} = require('playwright');
(async () => {
  const browser = await chromium.launch({headless:false});
  try {
    const page = await browser.newPage({viewport:{width:1280,height:800}});
    const errors=[];page.on('pageerror',error=>errors.push(error.message));
    await page.addInitScript(()=>{
      const pad={id:'QA Xbox standard',index:0,connected:true,mapping:'standard',axes:[0,0,0,0],buttons:Array.from({length:17},()=>({value:0,pressed:false,touched:false}))};
      Object.defineProperty(navigator,'getGamepads',{value:()=>[{...pad,timestamp:performance.now()}]});
      window.qaButton=(index,pressed)=>{pad.buttons[index]={value:pressed?1:0,pressed,touched:pressed};};
      window.qaConnect=()=>{const event=new Event('gamepadconnected');Object.defineProperty(event,'gamepad',{value:pad});window.dispatchEvent(event);};
    });
    await page.goto('http://127.0.0.1:8788/');
    await page.waitForFunction(()=>!document.querySelector('#local-button').disabled,{},{timeout:90000});
    await page.evaluate(()=>window.qaConnect());
    async function pad(button) {await page.evaluate(i=>qaButton(i,true),button);await page.waitForTimeout(100);await page.evaluate(i=>qaButton(i,false),button);await page.waitForTimeout(120);}
    async function seek(id) {
      const visited=[];
      for(let i=0;i<35;i++){if(await page.evaluate(id=>document.activeElement.id===id,id))return;visited.push(await page.evaluate(()=>({id:document.activeElement.id,tag:document.activeElement.tagName,label:document.activeElement.getAttribute('aria-label')})));await pad(13);}
      throw new Error(`Focus did not reach ${id}: ${JSON.stringify(visited)}`);
    }
    await seek('local-button');await pad(0);
    await page.waitForFunction(()=>document.querySelector('#local-setup').open);
    // Controller selection is reached by the same sequential navigation a player uses.
    for(let i=0;i<12;i++){
      if(await page.evaluate(()=>document.activeElement.getAttribute('aria-label')==='Контроллер P1'))break;
      await pad(13);
    }
    assert.equal(await page.evaluate(()=>document.activeElement.getAttribute('aria-label')),'Контроллер P1');
    await pad(15);assert.equal(await page.evaluate(()=>document.activeElement.value),'0');
    await seek('local-start');
    await page.evaluate(()=>qaButton(0,true));
    await page.waitForTimeout(500);
    assert.equal(await page.$eval('#local-setup',node=>node.open),true,'Held A must not activate before release');
    await page.evaluate(()=>qaButton(0,false));
    await page.waitForFunction(()=>window.GnomHost?.state?.mode==='local'&&GnomHost.state.phase==='racing',{},{timeout:60000});
    await page.waitForTimeout(500);
    const coastSpeed=await page.evaluate(()=>GnomHost.state.seats[0].speed);
    // A stationary racer may be pushed by bots; speed is not an input-neutrality oracle.
    assert.equal(await page.evaluate(()=>navigator.getGamepads()[0].buttons[0].pressed),false);
    await page.waitForTimeout(160);
    await page.evaluate(()=>qaButton(0,true));await page.waitForTimeout(1200);
    const speed=await page.evaluate(()=>GnomHost.state.seats[0].speed);assert.ok(speed>1,`Arcade A did not accelerate: ${speed}`);
    await page.evaluate(()=>qaButton(0,false));await pad(9);
    await page.waitForFunction(()=>document.querySelector('#local-pause').open&&GnomHost.state.paused);
    assert.equal(await page.evaluate(()=>document.activeElement.id),'local-resume');
    await page.screenshot({path:'/tmp/gnom-controller-pause.png'});
    await pad(1);await page.waitForFunction(()=>!GnomHost.state.paused);
    await pad(9);await page.waitForFunction(()=>GnomHost.state.paused);
    await pad(9);await page.waitForFunction(()=>!GnomHost.state.paused);
    await pad(9);await page.waitForFunction(()=>GnomHost.state.paused);
    await page.keyboard.press('Escape');await page.waitForFunction(()=>!GnomHost.state.paused);
    assert.deepEqual(errors,[]);
    console.log(JSON.stringify({result:'PASS',coastSpeed,speed,gamepad:'virtual standard mapping; physical Bluetooth not tested',screenshot:'/tmp/gnom-controller-pause.png'}));
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
