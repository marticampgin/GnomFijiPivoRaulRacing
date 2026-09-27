'use strict';
const assert = require('node:assert/strict');
const path = require('node:path');
const {chromium} = require('playwright');

(async () => {
  const browser = await chromium.launch({headless:true});
  const errors = [], failed = [];
  let checks = 0;
  try {
    const page = await browser.newPage({viewport:{width:1280,height:800}});
    page.on('pageerror', error => errors.push(error.message));
    page.on('response', response => { if (response.status() >= 400) failed.push(response.url()); });
    await page.setContent('<!doctype html><html lang="ru"><head><base href="http://127.0.0.1:8787/"></head><body></body></html>');
    for (const file of ['app.css','local-race.css','race-lobby.css','control-settings.css','ui-theme.css','race-overlays.css']) await page.addStyleTag({path:path.resolve(__dirname,'..',file)});
    for (const file of ['control-settings.js','race-lobby.js','local-race.js','menu-navigation.js']) await page.addScriptTag({path:path.resolve(__dirname,'..',file)});
    await page.evaluate(() => {
      window.messages = [];
      window.pad = {index:3,mapping:'standard',connected:true,axes:[0,0],buttons:Array.from({length:17},()=>({pressed:false}))};
      Object.defineProperty(navigator,'getGamepads',{value:()=>[null,null,null,pad]});
      window.fixture = GnomLocalUI.create({send:message=>messages.push(message),onStart:message=>messages.push(message)});
      fixture.updateDevices([{id:3,name:'Xbox'}]); fixture.showSetup();
      window.navigation = GnomMenuNavigation.create({scope:()=>Array.from(document.querySelectorAll('dialog[open]')).at(-1),onAction:action=>fixture.handleMenuAction(action)});
    });
    await page.waitForFunction(()=>document.activeElement.id === 'local-start');
    await page.waitForFunction(()=>Array.from(document.querySelectorAll('#local-setup img')).every(img=>img.complete&&img.naturalWidth>0));
    // Use a real navigation edge so screenshots include controller prompts.
    await page.evaluate(()=>pad.buttons[14].pressed=true); await page.waitForTimeout(80);
    await page.evaluate(()=>pad.buttons[14].pressed=false); await page.waitForTimeout(80);
    for (const viewport of [{width:1600,height:1000},{width:1280,height:800},{width:1024,height:760},{width:844,height:390},{width:390,height:844},{width:320,height:740}]) {
      await page.setViewportSize(viewport);
      await page.locator('#local-setup').evaluate(node=>node.scrollTop=0);
      const bounds = await page.locator('#local-setup').evaluate(node=>{
        const rect = selector => { const r=node.querySelector(selector).getBoundingClientRect(); return {top:r.top,bottom:r.bottom,left:r.left,right:r.right,height:r.height}; };
        return {width:node.clientWidth,scrollWidth:node.scrollWidth,body:rect('.lobby-body'),styles:rect('.lobby-styles'),race:rect('.lobby-race'),footer:rect('.lobby-footer'),header:rect('.lobby-header'),hints:rect('.menu-hints'),overflow:Array.from(node.querySelectorAll('button,strong')).filter(e=>e.getClientRects().length&&e.scrollWidth>e.clientWidth+2).map(e=>e.textContent)};
      });
      assert.ok(bounds.scrollWidth <= bounds.width+1,JSON.stringify({viewport,bounds})); checks++;
      assert.deepEqual(bounds.overflow,[],`text overflow at ${viewport.width}`); checks++;
      if (viewport.width > 760 && viewport.height > 570) {
        assert.ok(bounds.styles.bottom <= bounds.footer.top-4,JSON.stringify({viewport,bounds})); checks++;
        assert.ok(bounds.race.top >= bounds.body.top-1 && bounds.race.bottom <= bounds.footer.top-4,JSON.stringify({viewport,bounds})); checks++;
      }
      if (viewport.width > 760 && viewport.height <= 570) {
        assert.ok(bounds.body.bottom <= bounds.footer.top-4,JSON.stringify({viewport,bounds})); checks++;
      }
      assert.ok(bounds.footer.bottom <= viewport.height+1 && bounds.footer.top >= 0); checks++;
      await page.screenshot({path:`/tmp/gnom-lobby-verified-${viewport.width}.png`});
      console.log('layout',viewport.width,JSON.stringify(bounds));
    }
    await page.setViewportSize({width:1280,height:800});
    await page.locator('[data-focus-key="lobby-controls"]').click();
    await page.screenshot({path:'/tmp/gnom-lobby-verified-controls.png'});
    await page.keyboard.press('Escape');
    assert.equal(await page.evaluate(()=>document.activeElement.dataset.focusKey),'lobby-controls'); checks++;
    await page.locator('[data-focus-key="lobby-seat-1"]').click();
    assert.equal(await page.locator('[data-focus-key="lobby-layout"]').isVisible(),true); checks++;
    const clippedOptions=await page.locator('.lobby-race').evaluate(node=>node.scrollHeight>node.clientHeight+1);
    assert.equal(clippedOptions,false,'two-player desktop options should not need scrolling'); checks++;
    await page.evaluate(()=>fixture.showSetup({tutorial:true}));
    for (const viewport of [{width:1280,height:800},{width:390,height:844},{width:320,height:740}]) {
      await page.setViewportSize(viewport);
      const footer=await page.locator('.lobby-footer').evaluate(node=>{
        const r=node.getBoundingClientRect(),a=node.firstElementChild.getBoundingClientRect(),b=node.lastElementChild.getBoundingClientRect();
        return {left:r.left,right:r.right,backRight:a.right,startLeft:b.left,startRight:b.right,overflow:node.scrollWidth-node.clientWidth};
      });
      assert.ok(footer.left>=0&&footer.right<=viewport.width+1&&footer.startRight<=viewport.width&&footer.startLeft>=footer.backRight+8&&footer.overflow<=1,JSON.stringify({viewport,footer})); checks++;
    }
    assert.equal(await page.locator('#local-setup select').count(),0); checks++;
    assert.equal(await page.locator('.lobby-style').count(),4); checks++;
    assert.deepEqual(await page.evaluate(()=>messages),[]); checks++;
    assert.deepEqual(errors,[]); assert.deepEqual(failed,[]); checks+=2;
    console.log(`race lobby layout: ${checks}/${checks} passed; no race requested`);
  } finally { await browser.close(); }
})().catch(error=>{console.error(error);process.exitCode=1;});
