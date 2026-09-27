// Executed by Figma MCP with INPUT containing the foundation IDs and local PNG bytes.
const page = await figma.getNodeByIdAsync(INPUT.pageId);
await figma.setCurrentPageAsync(page);
await figma.loadFontAsync({family:'Arimo',style:'Regular'});
await figma.loadFontAsync({family:'Arimo',style:'Bold'});
await figma.loadFontAsync({family:'Arimo',style:'Bold Italic'});
if (page.children.some(n => n.name === '01 / HUD components')) throw new Error('Component board already exists');
const createdNodeIds = [], variables = {}, components = {}, images = {};
for (const [key,id] of Object.entries(INPUT.variables)) variables[key] = await figma.variables.getVariableByIdAsync(id);
const paint = (key,opacity=1) => figma.variables.setBoundVariableForPaint({type:'SOLID',color:{r:0,g:0,b:0},opacity},'color',variables[key]);
const remember = n => {createdNodeIds.push(n.id);return n;};
function text(parent,value,size=18,color='white',style='Bold') {
  const n=remember(figma.createText()); n.fontName={family:'Arimo',style}; n.fontSize=size;
  n.characters=value; n.letterSpacing={unit:'PIXELS',value:0}; n.lineHeight={unit:'PERCENT',value:110};
  n.fills=[paint(color)]; n.effects=[{type:'DROP_SHADOW',color:{r:0,g:0,b:0,a:.7},offset:{x:0,y:2},radius:4,visible:true,blendMode:'NORMAL'}];parent.appendChild(n);return n;
}
function box(parent,w,h,key='panel') {const n=remember(figma.createRectangle());parent.appendChild(n);n.resize(w,h);n.fills=[paint(key)];return n;}
function group(parent,direction='HORIZONTAL',gap=8) {const n=remember(figma.createAutoLayout(direction));parent.appendChild(n);n.fills=[];n.itemSpacing=gap;n.setBoundVariable('itemSpacing',variables['space'+gap]);n.counterAxisAlignItems='CENTER';return n;}
function component(name,w,h,x,y,description) {const n=remember(figma.createComponent());board.appendChild(n);n.name=name;n.resize(w,h);n.x=x;n.y=y;n.fills=[];n.clipsContent=false;n.description=description;components[name]=n.id;return n;}
for(const [name,bytes] of Object.entries(INPUT.assets))images[name]=figma.createImage(figma.base64Decode(bytes)).hash;
const board=remember(figma.createFrame());page.appendChild(board);board.name='01 / HUD components';board.x=200;board.y=1000;board.resize(1600,740);board.fills=[paint('bg')];
const heading=text(board,'HUD / Компоненты и состояния',32);heading.x=40;heading.y=28;
const note=text(board,'Клавиши зависят от устройства. Оба предмета независимы; эффект не занимает слот.',18,'muted','Regular');note.x=40;note.y=74;
for(const [index,id] of ['fanta','mermaid_rum','ice_rum','stroh80','lays_crab','bfg10k','empty'].entries()) {
  const c=component('HUD/Item/'+id,72,88,40+index*112,126,'Independent usable inventory slot. Incoming effects are never represented here.');
  const ring=remember(figma.createEllipse());c.appendChild(ring);ring.resize(72,72);ring.fills=[paint('bg',.9)];ring.strokes=[paint(id==='empty'?'muted':'white')];ring.strokeWeight=2;
  if(id!=='empty'){const icon=box(c,58,58);icon.name='Item artwork';icon.x=7;icon.y=7;icon.fills=[{type:'IMAGE',imageHash:images[id],scaleMode:'FIT'}];}
  else {const dash=text(c,'—',22,'muted');dash.x=24;dash.y=21;}
  const key=group(c);key.name='Input label';key.paddingLeft=8;key.paddingRight=8;key.paddingTop=2;key.paddingBottom=2;key.fills=[paint('bg')];key.x=22;key.y=64;
  text(key,'Q',14);
}
const crystal=component('HUD/Crystal',28,32,900,126,'Race-only turquoise crystal shard, not persistent shop currency.');
const shard=remember(figma.createVector());crystal.appendChild(shard);shard.vectorPaths=[{windingRule:'NONZERO',data:'M 14 0 L 26 10 L 22 25 L 14 32 L 3 22 L 2 10 Z'}];shard.fills=[paint('cyan')];
const facet=remember(figma.createVector());crystal.appendChild(facet);facet.vectorPaths=[{windingRule:'NONZERO',data:'M 14 0 L 14 32 L 22 25 L 26 10 Z'}];facet.fills=[paint('white',.45)];
const crystals=component('HUD/Crystals',130,36,1020,126,'Illustrative count only. Capacity and speed bonus require balance approval.');
const cr=group(crystals);const ci=remember(crystal.createInstance());cr.appendChild(ci);text(cr,'42',32);
const health=component('HUD/Health',152,32,40,296,'Durability is separate from crystal count. Text and bar both express the value.');
const hr=group(health,'HORIZONTAL',8);text(hr,'ПРОЧНОСТЬ',14,'muted');text(hr,'76',18);const hb=box(health,152,6,'line');hb.y=26;const hf=box(health,116,6,'cyan');hf.y=26;
const drift=component('HUD/Drift',180,40,280,296,'Three distinct charge levels. Level II shown; all styles may drift.');
const dr=group(drift);text(dr,'ДРИФТ',14);text(dr,'II',18,'lime');
const bars=group(drift,'HORIZONTAL',4);bars.y=28;
for(let i=0;i<3;i++)box(bars,56,6,i<2?'lime':'line');
const speed=component('HUD/Speed',152,54,540,280,'Speed and gear indicator. R communicates commanded reverse, not a new inventory action.');
const sr=group(speed,'HORIZONTAL',8);sr.counterAxisAlignItems='MAX';text(sr,'128',40);text(sr,'км/ч',14,'white');
const rev=component('HUD/Reverse',152,54,740,280,'Reverse begins after stopping while brake remains held. Value is illustrative.');
const rr=group(rev,'HORIZONTAL',8);text(rr,'R',32,'gold');text(rr,'12',40);text(rr,'км/ч',14);
const lap=component('HUD/Lap',138,62,990,270,'Local lap and elapsed time. Race length shown independently of other players.');
const lr=group(lap,'VERTICAL',4);lr.counterAxisAlignItems='MAX';const lrow=group(lr);text(lrow,'КРУГ',14);text(lrow,'2 / 3',24);text(lr,'01:24.680',18);
const rank=component('HUD/Rank',160,94,1210,256,'Rank is prominent. Player number and color identify the local viewport.');
const rankrow=group(rank,'HORIZONTAL',8);rankrow.counterAxisAlignItems='MAX';text(rankrow,'4',72,'lime','Bold Italic');const denominator=text(rankrow,'/ 10',22);denominator.name='Field size';
const ranklabel=text(rank,'МЕСТО',14);ranklabel.y=78;
for(const [i,[name,value,col]] of [['Burn','ГОРЕНИЕ  3 c','red'],['Shield','ЩИТ  4 c','cyan'],['Missile','РАКЕТА СЗАДИ','red'],['Respawn','ВОЗВРАТ  2 c','gold'],['Slipstream','ПОТОК','cyan'],['Start','СТАРТ: ТОЧНО','lime']].entries()) {
 const c=component('HUD/Status/'+name,220,40,40+(i%4)*360,430+Math.floor(i/4)*92,'Transient state indicator, separate from inventory. Durations are illustrative, not approved tuning.');
 const row=group(c);row.paddingLeft=12;row.paddingRight=12;row.paddingTop=8;row.paddingBottom=8;row.setBoundVariable('cornerRadius',variables.radius4);row.fills=[paint('bg',.88)];row.strokes=[paint(col)];row.strokeWeight=1;
 text(row,name==='Missile'?'!':name==='Shield'?'+':name==='Burn'?'!':'›',18,col);text(row,value,18,col);
}
const footer=text(board,'P1 • бирюзовый     P2 • золотой     P3 • красный     P4 • голубой. Номер обязателен: цвет не единственный признак.',18,'muted','Regular');footer.x=40;footer.y=660;
return {createdNodeIds,components,images,boardId:board.id,componentCount:Object.keys(components).length};
