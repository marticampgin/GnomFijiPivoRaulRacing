// Targeted corrections discovered by screenshot review: instance geometry and wide artwork crop.
const page=await figma.getNodeByIdAsync(INPUT.pageId);await figma.setCurrentPageAsync(page);
await figma.loadFontAsync({family:'Arimo',style:'Regular'});await figma.loadFontAsync({family:'Arimo',style:'Bold'});await figma.loadFontAsync({family:'Arimo',style:'Bold Italic'});
const board=await figma.getNodeByIdAsync(INPUT.boardId),base=await figma.getNodeByIdAsync(INPUT.components['HUD/Health']);
const createdNodeIds=[],mutatedNodeIds=[],variants={};board.resize(1600,920);mutatedNodeIds.push(board.id);
const variables={};for(const [k,id]of Object.entries(INPUT.variables))variables[k]=await figma.variables.getVariableByIdAsync(id);
const paint=key=>figma.variables.setBoundVariableForPaint({type:'SOLID',color:{r:0,g:0,b:0}},'color',variables[key]);
for(const [i,value] of [0,24,34,76,88,100].entries()){
 const c=base.clone();board.appendChild(c);c.name='HUD/Health/'+value;c.x=40+i*244;c.y=770;c.description='Exact visual durability state '+value+' / 100. Geometry belongs to the main component.';
 const t=c.findOne(n=>n.type==='TEXT'&&n.characters==='76');t.characters=String(value);
 const bar=c.findAllWithCriteria({types:['RECTANGLE']}).at(-1);bar.name='Health fill';bar.resize(Math.max(1,152*value/100),6);bar.visible=value>0;bar.fills=[paint(value<40?'red':'cyan')];variants[value]=c.id;createdNodeIds.push(c.id,...c.findAll(()=>true).map(n=>n.id));
}
const checks=[];
for(const f of INPUT.frames){const root=await figma.getNodeByIdAsync(f.id);for(const n of root.findAllWithCriteria({types:['INSTANCE']})){
 if(n.name==='HUD/Health'){const value=n.findAllWithCriteria({types:['TEXT']}).find(t=>/^\d+$/.test(t.characters)).characters;n.swapComponent(await figma.getNodeByIdAsync(variants[value]));mutatedNodeIds.push(n.id);checks.push({id:n.id,value,mainComponent:variants[value]});}
}
if(f.name==='04 / 2 players / horizontal'){for(const n of root.findAllWithCriteria({types:['RECTANGLE']})){if(n.name.startsWith('Approved concept art')){n.fills=[{type:'IMAGE',imageHash:INPUT.background,scaleMode:'CROP',imageTransform:[[1,0,0],[0,446/900,1-446/900]]}];mutatedNodeIds.push(n.id);}}}
}
// Recovery cannot simultaneously display a charged drift.
const recovery=await figma.getNodeByIdAsync('18:990');const di=recovery.findOne(n=>n.type==='INSTANCE'&&n.name==='HUD/Drift');
if(di){di.visible=false;mutatedNodeIds.push(di.id);}
return {createdNodeIds,mutatedNodeIds,healthVariants:variants,healthChecks:checks};
