// INPUT supplies the existing component IDs, token IDs and actual baked minimap.
const page=await figma.getNodeByIdAsync(INPUT.pageId);
await figma.setCurrentPageAsync(page);
await figma.loadFontAsync({family:'Arimo',style:'Regular'});
await figma.loadFontAsync({family:'Arimo',style:'Bold'});
await figma.loadFontAsync({family:'Arimo',style:'Bold Italic'});
if(page.children.some(n=>n.name==='02 / 1 player'))throw new Error('HUD screens already exist');
const vars={},comps={},frames=[],mutatedNodeIds=[];
for(const [k,id] of Object.entries(INPUT.variables))vars[k]=await figma.variables.getVariableByIdAsync(id);
for(const [k,id] of Object.entries(INPUT.components))comps[k]=await figma.getNodeByIdAsync(id);
const healthCaption=comps['HUD/Health'].findOne(n=>n.type==='TEXT'&&n.characters==='ПРЧ');
if(healthCaption){healthCaption.characters='ПРОЧНОСТЬ';mutatedNodeIds.push(healthCaption.id);}
const color=(key,opacity=1)=>figma.variables.setBoundVariableForPaint({type:'SOLID',color:{r:0,g:0,b:0},opacity},'color',vars[key]);
function text(p,str,size=18,key='white',style='Bold'){const n=figma.createText();p.appendChild(n);n.fontName={family:'Arimo',style};n.fontSize=size;n.characters=str;n.letterSpacing={unit:'PIXELS',value:0};n.lineHeight={unit:'PERCENT',value:110};n.fills=[color(key)];n.effects=[{type:'DROP_SHADOW',color:{r:0,g:0,b:0,a:.85},offset:{x:0,y:2},radius:4,visible:true,blendMode:'NORMAL'}];return n;}
function group(p,dir='HORIZONTAL',gap=8){const n=figma.createAutoLayout(dir);p.appendChild(n);n.fills=[];n.itemSpacing=gap;n.counterAxisAlignItems='CENTER';return n;}
function frame(p,name,w,h,x=0,y=0){const n=figma.createFrame();p.appendChild(n);n.name=name;n.resize(w,h);n.x=x;n.y=y;n.fills=[color('bg')];n.clipsContent=true;return n;}
function instance(p,key,x,y,overrides={}){const n=comps[key].createInstance();p.appendChild(n);n.x=x;n.y=y;for(const [from,to] of Object.entries(overrides)){for(const t of n.findAllWithCriteria({types:['TEXT']}))if(t.characters===from)t.characters=to;}return n;}
function badge(p,value,x,y,key='cyan'){const n=group(p);n.paddingLeft=12;n.paddingRight=12;n.paddingTop=6;n.paddingBottom=6;n.fills=[color('bg',.82)];n.setBoundVariable('cornerRadius',vars.radius4);n.x=x;n.y=y;text(n,value,16,key);return n;}
function minimap(p,w,h,x,y,players=4){const m=frame(p,'Map / baked route',w,h,x,y);m.fills=[];const margin=12;const pts=INPUT.route.map(v=>[margin+v[0]*(w-margin*2),margin+v[1]*(h-margin*2)]);const path='M '+pts.map(v=>v.map(z=>z.toFixed(2)).join(' ')).join(' L ')+' Z';const v=figma.createVector();m.appendChild(v);v.vectorPaths=[{windingRule:'NONZERO',data:path}];v.fills=[];v.strokes=[color('bg',.75)];v.strokeWeight=10;v.strokeJoin='ROUND';const line=figma.createVector();m.appendChild(line);line.vectorPaths=[{windingRule:'NONZERO',data:path}];line.fills=[];line.strokes=[color('white',.75)];line.strokeWeight=4;line.strokeJoin='ROUND';
 for(let i=0;i<players;i++){const a=pts[(13+i*7)%pts.length];const dot=figma.createEllipse();m.appendChild(dot);dot.resize(13,13);dot.x=a[0]-6;dot.y=a[1]-6;dot.fills=[color(['cyan','gold','red','blue'][i])];dot.strokes=[color('bg')];dot.strokeWeight=2;}
 const a=pts[5],b=pts[6],angle=Math.atan2(b[1]-a[1],b[0]-a[0]);const tip=figma.createVector();m.appendChild(tip);const rot=(dx,dy)=>[a[0]+dx*Math.cos(angle)-dy*Math.sin(angle),a[1]+dx*Math.sin(angle)+dy*Math.cos(angle)].join(' ');tip.vectorPaths=[{windingRule:'NONZERO',data:'M '+rot(8,0)+' L '+rot(-5,-6)+' L '+rot(-5,6)+' Z'}];tip.fills=[color('lime')];
 return m;}
const samples=[{rank:'4',crystal:'42',speed:'128',health:'76',items:['fanta','stroh80'],style:'ДРИФТ',status:'Slipstream'},{rank:'1',crystal:'68',speed:'142',health:'100',items:['bfg10k','ice_rum'],style:'СКОРОСТЬ',status:'Shield'},{rank:'8',crystal:'12',speed:'96',health:'34',items:['mermaid_rum','empty'],style:'УПРАВЛЯЕМОСТЬ',status:'Burn'},{rank:'6',crystal:'27',speed:'116',health:'88',items:['lays_crab','fanta'],style:'УСКОРЕНИЕ',status:null}];
const paneIds=[];
function pane(p,index,w,h,x,y,options={}){const s={...samples[index],...options};const n=frame(p,'P'+(index+1)+' / '+s.style,w,h,x,y);paneIds.push(n.id);
 const bg=figma.createRectangle();n.appendChild(bg);bg.name='Approved concept art / not gameplay capture';bg.resize(w,h);bg.fills=[{type:'IMAGE',imageHash:INPUT.background,scaleMode:'FILL'}];
 // Narrow edge washes keep white HUD legible without covering the driving corridor.
 for(const [side,height] of [['top',180],['bottom',152]]){const wash=figma.createRectangle();n.appendChild(wash);wash.name=side+' legibility';wash.resize(w,height);wash.y=side==='top'?0:h-height;wash.fills=[{type:'GRADIENT_LINEAR',gradientTransform:side==='top'?[[0,1,0],[-1,0,1]]:[[0,-1,1],[1,0,0]],gradientStops:[{position:0,color:{r:.02,g:.04,b:.03,a:.56}},{position:1,color:{r:.02,g:.04,b:.03,a:0}}]}];}
 const compact=h<=500,margin=compact?18:28;
 const slotrow=group(n,'HORIZONTAL',8);slotrow.name='Independent item slots';slotrow.x=margin;slotrow.y=margin;
 for(let i=0;i<2;i++){const it=instance(slotrow,'HUD/Item/'+s.items[i],0,0,{'Q':index===0?(i===0?'Q':'E'):(i===0?'LB':'RB')});}
 instance(n,'HUD/Crystals',margin,margin+98,{'42':s.crystal});
 const tag=badge(n,'P'+(index+1)+'  /  '+s.style,0,margin,['cyan','gold','red','blue'][index]);tag.x=(w-tag.width)/2;
 instance(n,'HUD/Lap',w-margin-138,margin,{'2 / 3':s.lap||'2 / 3'});
 const rank=instance(n,'HUD/Rank',margin,h-margin-126,{'4':s.rank});
 for(const t of rank.findAllWithCriteria({types:['TEXT']}))if(t.characters===s.rank)t.fills=[color(['cyan','gold','red','blue'][index])];
 const hp=instance(n,'HUD/Health',margin,h-margin-32,{'76':s.health});const hf=hp.findAllWithCriteria({types:['RECTANGLE']}).at(-1);if(hf){hf.resize(Math.max(1,152*Number(s.health)/100),6);hf.fills=[color(Number(s.health)<40?'red':'cyan')];}
 instance(n,'HUD/Drift',(w-180)/2,h-margin-40);
 instance(n,s.reverse?'HUD/Reverse':'HUD/Speed',w-margin-152,h-margin-54,{'128':s.speed});
 minimap(n,compact?118:160,compact?118:160,w-margin-(compact?118:160),h-margin-(compact?118:160)-70,4);
 if(s.status)instance(n,'HUD/Status/'+s.status,margin,margin+148);
 if(s.missile)instance(n,'HUD/Status/Missile',(w-220)/2,compact?76:98);
 if(s.respawn)instance(n,'HUD/Status/Respawn',(w-220)/2,h*.43);
 return n;}
function board(name,col,row){const n=frame(page,name,1600,900,200+col*1800,1900+row*1100);frames.push({id:n.id,name:n.name,width:1600,height:900});return n;}
let b=board('02 / 1 player',0,0);pane(b,0,1600,900,0,0,{missile:true});
b=board('03 / 2 players / vertical',1,0);pane(b,0,796,900,0,0);pane(b,1,796,900,804,0,{missile:true});
b=board('04 / 2 players / horizontal',0,1);pane(b,0,1600,446,0,0);pane(b,1,1600,446,0,454);
b=board('05 / 3 players + overview',1,1);pane(b,0,796,446,0,0);pane(b,1,796,446,804,0);pane(b,2,796,446,0,454);
const overview=frame(b,'Shared race overview',796,446,804,454);const oh=text(overview,'ЗАМОК И ВОДОПАДЫ',28);oh.x=32;oh.y=24;minimap(overview,300,290,34,94,3);const standings=group(overview,'VERTICAL',16);standings.x=370;standings.y=116;standings.counterAxisAlignItems='MIN';text(standings,'МЕСТА',14,'muted');for(const [label,col] of [['1   P2    СКОРОСТЬ','gold'],['4   P1    ДРИФТ','cyan'],['8   P3    УПРАВЛЯЕМОСТЬ','red']])text(standings,label,20,col);const info=text(overview,'3 игрока + 7 ботов',18,'muted');info.x=370;info.y=320;
b=board('06 / 4 players / quad',0,2);for(let i=0;i<4;i++)pane(b,i,796,446,(i%2)*804,Math.floor(i/2)*454,{missile:i===1});
b=board('07 / States / missile burn reverse recovery',1,2);pane(b,0,796,446,0,0,{missile:true,status:null});pane(b,1,796,446,804,0,{status:'Burn',health:'24'});pane(b,2,796,446,0,454,{reverse:true,status:null,speed:'12'});pane(b,3,796,446,804,454,{respawn:true,status:null,health:'0',speed:'0',crystal:'0',items:['empty','empty']});
const createdNodeIds=[];for(const f of frames){const n=await figma.getNodeByIdAsync(f.id);createdNodeIds.push(n.id,...n.findAll(()=>true).map(c=>c.id));}
const overflow=[];for(const id of paneIds){const n=await figma.getNodeByIdAsync(id);for(const c of n.children){if(c.x<-.1||c.y<-.1||c.x+c.width>n.width+.1||c.y+c.height>n.height+.1)overflow.push({pane:id,node:c.id,name:c.name});}}
return {createdNodeIds,mutatedNodeIds,frames,paneIds,overflow,instanceCount:frames.reduce((sum,f)=>sum+page.findOne(n=>n.id===f.id).findAllWithCriteria({types:['INSTANCE']}).length,0)};
