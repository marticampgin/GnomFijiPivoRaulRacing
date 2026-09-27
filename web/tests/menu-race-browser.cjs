'use strict';
const assert = require('node:assert/strict');
const {chromium} = require('playwright');
const sharp = require('sharp');
const menuOnly = process.env.GNOM_QA_MENU_ONLY === '1';
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
    const url = process.env.GNOM_QA_URL || 'http://127.0.0.1:8787/';
    await page.goto(url);
    assert.equal(new URL(page.url()).origin,new URL(url).origin);
    assert.match(await page.title(),/GNOM FIJI/i);
    await page.waitForFunction(()=>!document.querySelector('#local-button').disabled,{},{timeout:90000});
    await page.evaluate(()=>window.qaConnect());
    async function pad(button) {await page.evaluate(i=>qaButton(i,true),button);await page.waitForTimeout(100);await page.evaluate(i=>qaButton(i,false),button);await page.waitForTimeout(120);}
    await page.waitForFunction(()=>document.activeElement.id==='local-button');
    await page.screenshot({path:'/tmp/gnom-controller-live-hub-1280.png'});
    await page.setViewportSize({width:390,height:844});
    await page.screenshot({path:'/tmp/gnom-controller-live-hub-390.png'});
    await page.setViewportSize({width:1280,height:800});await pad(0);
    await page.waitForFunction(()=>document.querySelector('#local-setup').open);
    // Do not manually select the controller: this is the original auto-default regression.
    await page.waitForFunction(()=>document.querySelector('[aria-label="Контроллер P1"]').getAttribute('aria-valuetext')==='Геймпад 1');
    await page.waitForFunction(()=>document.activeElement.id==='local-start');
    await page.screenshot({path:'/tmp/gnom-controller-live-setup-1280.png'});
    await page.setViewportSize({width:390,height:844});
    await page.screenshot({path:'/tmp/gnom-controller-live-setup-390.png'});
    assert.ok(await page.locator('#local-setup').evaluate(node=>node.scrollWidth<=node.clientWidth+1),'Setup horizontal overflow');
    await page.setViewportSize({width:1280,height:800});
    // Exercise the visible spatial route with pad edges only, without click/focus shortcuts.
    await pad(14);
    assert.equal(await page.evaluate(()=>document.activeElement.id),'local-setup-back','Left follows the footer actions');
    await pad(12);
    assert.equal(await page.evaluate(()=>document.activeElement.dataset.styleId),'handling','Up from Back reaches the style strip');
    await pad(15);await pad(15);
    assert.equal(await page.evaluate(()=>document.activeElement.dataset.styleId),'speed');
    await pad(0);
    assert.equal(await page.locator('[data-style-id="speed"]').getAttribute('aria-pressed'),'true');
    await pad(15);await pad(15);
    assert.equal(await page.evaluate(()=>document.activeElement.dataset.focusKey),'lobby-controls','Right from the style strip reaches player controls');
    await pad(0);
    await page.waitForFunction(()=>document.querySelector('#local-player-controls').open);
    await pad(1);
    await page.waitForFunction(()=>!document.querySelector('#local-player-controls').open);
    assert.equal(await page.evaluate(()=>document.activeElement.dataset.focusKey),'lobby-controls','Back restores the controls button');
    await pad(13);
    assert.equal(await page.evaluate(()=>document.activeElement.id),'local-start');
    await pad(12);
    assert.equal(await page.evaluate(()=>document.activeElement.dataset.focusKey),'lobby-controls','Up from Start returns directly to player controls');
    await pad(13);
    assert.equal(await page.evaluate(()=>document.activeElement.id),'local-start','Down from Controls returns directly to Start');
    if (menuOnly) {
      assert.notEqual(await page.evaluate(()=>GnomHost.state?.mode),'local','Menu-only mode must never start a local race');
      await page.screenshot({path:'/tmp/gnom-controller-live-menu-only-1280.png'});
      await pad(1);
      await page.waitForFunction(()=>!document.querySelector('#local-setup').open);
      assert.deepEqual(errors,[]);
      console.log(JSON.stringify({result:'PASS',scope:'menu-only; no race start command',url,style:'speed',gamepad:'virtual standard mapping; physical Bluetooth not tested',screenshot:'/tmp/gnom-controller-live-menu-only-1280.png'}));
      return;
    }
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
    const speed=await page.evaluate(()=>GnomHost.state.seats[0].speed);assert.ok(speed>coastSpeed+10,`Arcade A did not accelerate beyond initial coast: ${coastSpeed} -> ${speed}`);
    await page.screenshot({path:'/tmp/gnom-controller-live-racing-1280.png'});
    const pixels=await sharp(await page.screenshot({clip:{x:480,y:260,width:320,height:240}})).stats();
    assert.ok(pixels.channels.slice(0,3).every(channel=>channel.stdev>8),'Rendered race pixels must contain nonblank scene detail');
    await page.evaluate(()=>qaButton(0,false));await pad(9);
    await page.waitForFunction(()=>document.querySelector('#local-pause').open&&GnomHost.state.paused);
    assert.equal(await page.evaluate(()=>document.activeElement.id),'local-resume');
    await page.screenshot({path:'/tmp/gnom-controller-pause.png'});
    await page.setViewportSize({width:390,height:844});
    await page.screenshot({path:'/tmp/gnom-controller-live-pause-390.png'});
    assert.ok(await page.locator('#local-pause').evaluate(node=>node.scrollWidth<=node.clientWidth+1),'Pause horizontal overflow');
    await page.setViewportSize({width:1280,height:800});
    await pad(13);await pad(0);
    await page.waitForFunction(()=>document.querySelector('#local-settings').open);
    await pad(1);
    await page.waitForFunction(()=>!document.querySelector('#local-settings').open&&document.querySelector('#local-pause').open);
    await pad(1);await page.waitForFunction(()=>!GnomHost.state.paused);
    await pad(9);await page.waitForFunction(()=>GnomHost.state.paused);
    await pad(9);await page.waitForFunction(()=>!GnomHost.state.paused);
    await pad(9);await page.waitForFunction(()=>GnomHost.state.paused);
    await page.keyboard.press('Escape');await page.waitForFunction(()=>!GnomHost.state.paused);
    assert.deepEqual(errors,[]);
    console.log(JSON.stringify({result:'PASS',url,coastSpeed,speed,gamepad:'virtual standard mapping; physical Bluetooth not tested',screenshot:'/tmp/gnom-controller-pause.png'}));
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
