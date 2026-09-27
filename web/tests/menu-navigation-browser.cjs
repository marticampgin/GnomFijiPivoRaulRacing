'use strict';
const assert = require('node:assert/strict');
const path = require('node:path');
const {chromium} = require('playwright');

(async () => {
  const browser = await chromium.launch({headless:true});
  let checks = 0;
  const errors = [];
  try {
    const page = await browser.newPage({viewport:{width:1280,height:800}});
    page.on('pageerror', error => errors.push(error.message));
    await page.setContent(`<main id="hub"><button id="play" data-menu-default>Play</button><button disabled>Unavailable</button><button id="next">Next</button></main><dialog id="dialog"><button id="close">Close</button><select id="select"><option value="a">A</option><option value="b">B</option></select><input id="range" type="range" min="0" max="10" value="5"><details><summary id="details">Controls</summary><button id="inside">Reset</button></details><button id="ready" data-menu-device="1">P2 Ready</button></dialog><canvas id="canvas" tabindex="0"></canvas>`);
    await page.addStyleTag({content:'#hub{display:grid;width:300px;gap:12px}#dialog[open]{display:grid;width:320px;gap:12px}#dialog details{display:block}#dialog details>button{display:block;margin-top:12px}button,select,input,summary{min-height:32px}'});
    await page.addScriptTag({path:path.resolve(__dirname,'../menu-navigation.js')});
    await page.addScriptTag({path:path.resolve(__dirname,'../control-settings.js')});
    await page.evaluate(() => {
      window.pressed = [];
      window.axes = [0,0];
      Object.defineProperty(navigator,'getGamepads',{value:()=>[{index:0,mapping:'standard',connected:true,axes:window.axes,buttons:Array.from({length:16},(_,i)=>({pressed:window.pressed.includes(i)}))}]});
      const hub=document.querySelector('#hub'), dialog=document.querySelector('#dialog');
      window.clicks=0;window.changes=0;window.racing=false;
      document.querySelector('#ready').onclick=()=>window.clicks++;
      document.querySelector('#play').onclick=()=>dialog.showModal();
      document.querySelector('#close').onclick=()=>dialog.close();
      document.querySelector('#select').onchange=()=>window.changes++;
      window.navigation=GnomMenuNavigation.create({scope:()=>window.racing?null:dialog.open?dialog:hub});
    });
    async function focus(id) { await page.waitForFunction(id=>document.activeElement.id===id,id); checks++; }
    async function pad(button) {
      await page.evaluate(button=>{window.pressed=[button];},button);
      await page.waitForTimeout(45);
      await page.evaluate(()=>{window.pressed=[];});
      await page.waitForTimeout(45);
    }
    await focus('play');
    await pad(13);await focus('next');
    await pad(12);await focus('play');
    await pad(0);await focus('close');
    await pad(13);await focus('select');
    await pad(15);assert.equal(await page.$eval('#select',n=>n.value),'b');checks++;
    assert.equal(await page.evaluate(()=>window.changes),1);checks++;
    await pad(13);await focus('range');
    await pad(15);assert.equal(await page.$eval('#range',n=>n.value),'6');checks++;
    await pad(13);await focus('details');
    await pad(13);await focus('ready');
    await pad(12);await focus('details');
    await pad(0);await pad(13);await focus('inside');
    await pad(13);await focus('ready');
    await pad(0);assert.equal(await page.evaluate(()=>window.clicks),0);checks++;
    await pad(1);assert.equal(await page.$eval('#dialog',n=>n.open),false);checks++;
    await focus('play');
    await page.keyboard.press('Enter');await focus('ready');
    await page.focus('#close');
    await page.keyboard.press('ArrowDown');await focus('select');
    await page.keyboard.press('ArrowLeft');assert.equal(await page.$eval('#select',n=>n.value),'a');checks++;
    await page.keyboard.press('Escape');await focus('play');
    await page.evaluate(()=>{window.racing=true;document.querySelector('#canvas').focus();});
    await pad(13);await pad(0);await focus('canvas');
    assert.equal(await page.$eval('#dialog',n=>n.open),false);checks++;
    await page.evaluate(()=>{
      window.racing=false;
      const editor=GnomControlSettings.create();document.querySelector('#hub').append(editor.node);
    });
    assert.equal(await page.locator('.control-bindings').innerText().then(text=>text.includes('Space / C')),true);checks++;
    for (const viewport of [{width:1280,height:800},{width:390,height:844}]) {
      await page.setViewportSize(viewport);
      await page.addStyleTag({path:path.resolve(__dirname,'../control-settings.css')});
      assert.equal(await page.locator('.control-bindings').isVisible(),true);checks++;
    }
    await page.evaluate(()=>window.navigation.destroy());
    await page.evaluate(()=>{const base=document.createElement('base');base.href='http://127.0.0.1:8787/';document.head.append(base);});
    await page.addStyleTag({path:path.resolve(__dirname,'../app.css')});
    await page.addStyleTag({path:path.resolve(__dirname,'../local-race.css')});
    await page.addStyleTag({path:path.resolve(__dirname,'../race-lobby.css')});
    await page.addStyleTag({path:path.resolve(__dirname,'../ui-theme.css')});
    await page.addStyleTag({path:path.resolve(__dirname,'../race-overlays.css')});
    await page.addScriptTag({path:path.resolve(__dirname,'../race-lobby.js')});
    await page.addScriptTag({path:path.resolve(__dirname,'../local-race.js')});
    await page.evaluate(()=>{
      document.querySelector('#hub').hidden=true;
      window.fixture=GnomLocalUI.create({send(){}});fixture.showSetup();
      window.navigation=GnomMenuNavigation.create({scope:()=>Array.from(document.querySelectorAll('dialog[open]')).at(-1)});
    });
    await page.getByRole('spinbutton',{name:'Игроки',exact:true}).focus();
    await page.keyboard.press('ArrowRight');
    assert.equal(await page.getByRole('spinbutton',{name:'Игроки',exact:true}).getAttribute('aria-valuetext'),'2');checks++;
    assert.equal(await page.getByRole('spinbutton',{name:'Экран',exact:true}).isVisible(),true,'Two players expose split-screen orientation');checks++;
    await page.keyboard.press('Enter');
    assert.equal(await page.getByRole('spinbutton',{name:'Игроки',exact:true}).getAttribute('aria-valuetext'),'2','Enter must not unexpectedly cycle a choice');checks++;
    assert.match(await page.locator('#local-setup .menu-hints').innerText(),/← →.*Изменить/s);checks++;
    await page.getByRole('spinbutton',{name:'Игроки',exact:true}).evaluate(node=>node.dispatchEvent(new CustomEvent('menu-adjust',{bubbles:true,detail:{amount:-1}})));
    assert.equal(await page.getByRole('spinbutton',{name:'Игроки',exact:true}).getAttribute('aria-valuetext'),'1');checks++;
    assert.equal(await page.locator('#local-setup select').count(),0,'Lobby choices must not reopen native select popups');checks++;
    for (const viewport of [{width:1280,height:800},{width:390,height:844}]) {
      await page.setViewportSize(viewport);
      const bounds=await page.locator('#local-setup').evaluate(node=>({width:node.clientWidth,scrollWidth:node.scrollWidth,right:node.getBoundingClientRect().right,left:node.getBoundingClientRect().left}));
      assert.ok(bounds.scrollWidth<=bounds.width+1&&bounds.left>=0&&bounds.right<=viewport.width,`Dialog overflows at ${viewport.width}`);checks++;
      assert.equal(await page.getByRole('group',{name:'Стиль P1'}).getByRole('button').count(),4,'All four styles remain directly available');checks++;
      await page.waitForFunction(()=>Array.from(document.querySelectorAll('#local-setup img')).every(image=>image.complete&&image.naturalWidth>0));
      await page.screenshot({path:`/tmp/gnom-controller-lobby-${viewport.width}.png`});
      await page.getByRole('button',{name:'Управление P1',exact:true}).click();
      await page.waitForFunction(()=>document.querySelector('#local-player-controls').open);
      const controlsBounds=await page.locator('#local-player-controls').evaluate(node=>({width:node.clientWidth,scrollWidth:node.scrollWidth,right:node.getBoundingClientRect().right,left:node.getBoundingClientRect().left}));
      assert.ok(controlsBounds.scrollWidth<=controlsBounds.width+1&&controlsBounds.left>=0&&controlsBounds.right<=viewport.width,`Controls dialog overflows at ${viewport.width}`);checks++;
      assert.equal(await page.locator('#local-player-controls .control-bindings').isVisible(),true);checks++;
      await page.screenshot({path:`/tmp/gnom-controller-settings-${viewport.width}.png`});
      await page.keyboard.press('Escape');
      await page.waitForFunction(()=>!document.querySelector('#local-player-controls').open);
      assert.equal(await page.locator('#local-setup').evaluate(node=>node.open),true,'Closing player controls returns to the lobby');checks++;
      assert.equal(await page.evaluate(()=>document.activeElement.dataset.focusKey),'lobby-controls');checks++;
    }
    await page.evaluate(()=>{navigation.destroy();fixture.destroy();});
    assert.deepEqual(errors,[]);checks++;
    console.log(`menu DOM navigation: ${checks}/${checks} passed`);
  } finally { await browser.close(); }
})().catch(error=>{console.error(error);process.exitCode=1;});
