const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');
const root = __dirname;
const C = { bg:'#131715',panel:'#202623',line:'#3b4540',muted:'#a8b7af',white:'#f5f7f4',lime:'#e5ff58',cyan:'#64e3db',red:'#ff877b' };
const esc = s => String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
const text=(x,y,s,size=20,color=C.white,weight=400,more='')=>`<text x="${x}" y="${y}" font-family="Arial, sans-serif" font-size="${size}" font-weight="${weight}" fill="${color}" ${more}>${esc(s)}</text>`;
const rect=(x,y,w,h,fill=C.panel,stroke='none',r=0,op=1)=>`<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" fill="${fill}" stroke="${stroke}" opacity="${op}"/>`;
const line=(x,y,x2,y2,color=C.line,w=1)=>`<path d="M${x} ${y}L${x2} ${y2}" fill="none" stroke="${color}" stroke-width="${w}"/>`;
const circle=(x,y,r,fill,stroke='none',w=1)=>`<circle cx="${x}" cy="${y}" r="${r}" fill="${fill}" stroke="${stroke}" stroke-width="${w}"/>`;
const tag=(x,y,s,color=C.cyan,w=112)=>rect(x,y,w,28,color,'none',2,.13)+text(x+12,y+20,s,13,color,700);
const btn=(x,y,w,s,primary=true)=>rect(x,y,w,56,primary?C.lime:C.panel,primary?'none':C.line,4)+text(x+22,y+35,s,18,primary?C.bg:C.white,700)+text(x+w-35,y+35,'›',27,primary?C.bg:C.white,700);
const stat=(x,y,label,value,max=100)=>text(x,y,label,16,C.muted)+text(x+318,y,String(value),17,C.white,700,'text-anchor="end"')+rect(x,y+14,318,5,C.line)+rect(x,y+14,318*value/max,5,C.cyan);
const crystal=(x,y,s=1,color=C.cyan)=>`<g transform="translate(${x} ${y}) scale(${s})"><path d="M0 -24L18 -7L11 19L0 28L-11 19L-18 -7Z" fill="${color}"/><path d="M0 -24L5 -5L0 28L-6 -5Z" fill="#ffffff" opacity=".55"/><path d="M-18 -7L5 -5L18 -7" fill="none" stroke="#fff" opacity=".5"/></g>`;
const base=(title,body)=>`<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1600" height="900" viewBox="0 0 1600 900"><title>${esc(title)}</title><defs><linearGradient id="shade"><stop stop-color="#0d1613" stop-opacity=".97"/><stop offset=".6" stop-color="#0d1613" stop-opacity=".42"/><stop offset="1" stop-color="#0d1613" stop-opacity="0"/></linearGradient><linearGradient id="bottom" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#131715" stop-opacity="0"/><stop offset="1" stop-color="#131715"/></linearGradient></defs>${rect(0,0,1600,900,C.bg)}${body}</svg>`;
const top=(active='ГОНКА')=>rect(0,0,1600,86,C.bg)+text(40,40,'GNOM FIJI',24,C.lime,900)+text(41,62,'P.I.V.O RAUL RACING',10,C.muted,700)+['ГОНКА','ГАРАЖ','КАМПАНИЯ','МАГАЗИН'].map((s,i)=>text(298+i*150,50,s,15,s===active?C.white:C.muted,700)+(s===active?rect(296+i*150,81,98,4,C.lime):'')).join('')+crystal(1200,42,.4)+text(1220,49,'1 240',18,C.white,700)+line(1300,26,1300,60)+circle(1353,43,19,C.cyan)+text(1353,50,'01',15,C.bg,700,'text-anchor="middle"')+text(1386,40,'Игрок 01',15,C.white,700)+text(1386,61,'Рейтинг 1 280',12,C.muted)+line(0,86,1600,86);
const foot=(s='Европа · 34 мс')=>line(40,848,1560,848)+text(40,877,'GNOM FIJI  /  P.I.V.O RAUL RACING',11,C.muted,700)+text(1560,877,s,13,C.muted,400,'text-anchor="end"');
async function main(){
  const images={};
  for(const name of ['race','kart']){
    const jpg=await sharp(path.join(root,'assets',`${name}-concept.png`)).jpeg({quality:90}).toBuffer();
    fs.writeFileSync(path.join(root,'assets',`${name}-concept.jpg`),jpg);
    images[name]=`data:image/jpeg;base64,${jpg.toString('base64')}`;
  }
  const img=(name,x,y,w,h,mode='xMidYMid slice')=>`<image x="${x}" y="${y}" width="${w}" height="${h}" preserveAspectRatio="${mode}" xlink:href="${images[name]}"/>`;
  const out=[];
  function save(id,title,body){out.push({id,title});fs.writeFileSync(path.join(root,'frames',`${id}.svg`),base(title,body));}

  save('01-hub','Главный экран',img('race',0,86,1600,814)+rect(0,86,1220,814,'url(#shade)')+rect(0,680,1600,220,'url(#bottom)')+top()+
    tag(54,128,'ОНЛАЙН',C.lime)+text(50,239,'GNOM FIJI',92,C.white,900)+text(54,285,'P.I.V.O RAUL RACING',27,C.lime,700)+
    text(56,371,'ТВОЯ СЛЕДУЮЩАЯ ГОНКА',14,C.muted,700)+text(53,425,'Рейтинговый заезд',38,C.white,700)+text(56,463,'10 гонщиков · 3 круга',19,C.white)+
    btn(56,500,382,'НАЙТИ ГОНКУ')+text(57,592,'Рейтинг',15,C.muted)+text(57,635,'1 280',38,C.white,700)+text(243,592,'Мощность сборки',15,C.muted)+text(243,635,'420',38,C.white,700)+
    line(56,668,544,668)+text(56,709,'Комната друзей',21,C.white,700)+text(510,709,'↗',25,C.cyan)+text(56,752,'Продолжить кампанию',21,C.white,700)+text(510,752,'↗',25,C.cyan)+
    rect(1160,683,388,126,C.bg,C.line,4,.95)+tag(1180,701,'ВЫБРАНО',C.cyan,100)+text(1180,758,'Машина 01',25,C.white,700)+text(1180,788,'Сборка: управляемость',15,C.muted)+foot());

  save('02-garage','Гараж и сборка',img('kart',275,159,960,570,'xMidYMid meet')+top('ГАРАЖ')+text(40,138,'ГАРАЖ',34,C.white,700)+tag(207,113,'3 МАШИНЫ',C.cyan,125)+
    rect(40,182,254,599,'#19201b',C.line,4)+['Машины','Персонажи','Детали','Окраска','Эмоции и гудки'].map((s,i)=>rect(53,201+i*60,228,48,i===2?C.lime:'#19201b','none',3)+text(73,232+i*60,s,17,i===2?C.bg:C.muted,700)).join('')+
    text(65,568,'СБОРКА 01',12,C.muted,700)+text(65,607,'Управляемость',21,C.white,700)+text(65,652,'Мощность',15,C.muted)+text(255,652,'420',22,C.cyan,700,'text-anchor="end"')+btn(61,702,211,'ВЫБРАТЬ',false)+
    text(338,200,'Машина 01',35,C.white,700)+text(340,230,'Персонаж 01',16,C.muted)+tag(974,175,'УСТАНОВЛЕНО',C.lime,145)+
    rect(1170,172,390,609,C.panel,C.line,4)+text(1196,213,'ХАРАКТЕРИСТИКИ',16,C.white,700)+
    [['Скорость',72],['Ускорение',61],['Управляемость',88],['Дрифт',81],['Прочность',56]].map(([s,v],i)=>stat(1196,259+i*68,s,v)).join('')+
    line(1196,593,1535,593)+text(1196,632,'Подбор соперников',17,C.white,700)+text(1196,662,'Рейтинг + оснащение',16,C.muted)+text(1196,696,'Онлайн: нормализованная база',15,C.cyan)+text(1196,724,'Бонусы деталей сохраняются',15,C.muted)+
    [['Двигатель','Уровень 03'],['Турбина','Уровень 02'],['Шины','Уровень 04'],['Корпус','Уровень 02']].map(([s,v],i)=>rect(328+i*207,688,195,93,C.panel,i===2?C.lime:C.line,4)+text(344+i*207,719,s,17,C.white,700)+text(344+i*207,750,v,14,i===2?C.lime:C.muted)).join('')+foot());

  const players=[['Игрок 01','1 280','420','ВЫ'],['Игрок 02','1 312','425',''],['Игрок 03','1 241','413',''],['Игрок 04','1 296','419',''],['Игрок 05','1 270','427',''],['Игрок 06','1 289','418',''],['Бот 01','1 275','422','БОТ'],['Бот 02','1 291','416','БОТ'],['Бот 03','1 265','424','БОТ'],['Бот 04','1 302','421','БОТ']];
  save('03-ranked-lobby','Рейтинговое лобби',top()+text(40,142,'РЕЙТИНГОВЫЙ ЗАЕЗД',34,C.white,700)+tag(490,115,'10 / 10',C.lime,96)+
    text(40,184,'Соперники найдены',20,C.cyan)+text(1538,147,'СТАРТ ЧЕРЕЗ 08',23,C.lime,700,'text-anchor="end"')+
    text(66,239,'ГОНЩИК',12,C.muted,700)+text(621,239,'РЕЙТИНГ',12,C.muted,700)+text(780,239,'МОЩНОСТЬ',12,C.muted,700)+
    players.map((p,i)=>rect(40,253+i*53,882,48,i===0?'#303b23':i%2?C.bg:C.panel,'none',3)+circle(70,277+i*53,13,p[3]==='БОТ'?C.line:C.cyan)+text(99,284+i*53,p[0],18,C.white,600)+text(647,284+i*53,p[1],18,C.white,600)+text(812,284+i*53,p[2],18,C.muted)+(p[3]?tag(384,263+i*53,p[3],p[3]==='ВЫ'?C.lime:C.muted,64):'')).join('')+
    img('race',965,214,595,336)+rect(965,478,595,73,'url(#bottom)')+text(989,521,'Трасса 01',26,C.white,700)+text(965,595,'3 КРУГА',15,C.lime,700)+text(1125,595,'6 ИГРОКОВ + 4 БОТА',15,C.muted,700)+
    text(965,648,'Рейтинг меняется по результату',20,C.white,700)+text(965,680,'Учитывается сила соперников.',17,C.muted)+text(965,710,'Очки за ботов и людей равны.',17,C.muted)+btn(965,744,595,'ОТМЕНИТЬ УЧАСТИЕ',false)+foot('Европа · 34 мс · Соединение установлено'));

  save('04-race-hud','Гонка: основной HUD',img('race',0,0,1600,900)+
    rect(28,28,254,130,C.bg,'none',5,.93)+text(50,98,'04',70,C.white,900)+text(157,96,'/ 10',28,C.muted,700)+text(51,135,'ПОЗИЦИЯ',12,C.lime,700)+
    rect(657,28,286,70,C.bg,'none',5,.92)+text(678,56,'КРУГ',12,C.muted,700)+text(678,82,'2 / 3',24,C.white,700)+line(770,43,770,81)+text(794,56,'ВРЕМЯ',12,C.muted,700)+text(794,82,'01:42.386',24,C.white,700)+
    rect(1320,28,252,222,C.bg,'none',5,.9)+text(1342,57,'ТРАССА 01',12,C.muted,700)+`<path d="M1360 128 C1360 67 1490 70 1534 112 S1502 215 1450 208 S1320 180 1376 159 S1490 175 1490 129 S1420 112 1415 143" fill="none" stroke="#64746a" stroke-width="14" stroke-linecap="round"/>`+circle(1401,96,6,C.white)+circle(1490,135,6,C.white)+circle(1450,208,6,C.white)+circle(1377,159,9,C.lime,C.bg,3)+
    rect(28,190,235,162,C.bg,'none',5,.85)+[['01','Игрок 03','−2.8'],['02','Бот 01','−1.4'],['03','Игрок 02','−0.6'],['04','Игрок 01','ВЫ']].map(([n,s,t],i)=>text(43,219+i*36,n,16,i===3?C.lime:C.muted,700)+text(74,219+i*36,s,16,i===3?C.lime:C.white,600)+text(246,219+i*36,t,14,i===3?C.lime:C.muted,400,'text-anchor="end"')).join('')+
    rect(28,761,312,111,C.bg,'none',5,.95)+text(48,793,'ПРОЧНОСТЬ',12,C.muted,700)+text(315,793,'76 / 100',17,C.white,700,'text-anchor="end"')+rect(48,811,268,10,C.line,'none',2)+rect(48,811,204,10,C.cyan,'none',2)+text(48,850,'Машина 01',16,C.white,700)+
    rect(548,791,504,81,C.bg,'none',5,.94)+text(571,820,'ДРИФТ',14,C.lime,700)+text(1027,820,'УСКОРЕНИЕ II',14,C.lime,700,'text-anchor="end"')+[0,1,2].map(i=>rect(571+i*155,837,144,12,i<2?C.lime:C.line,'none',2)).join('')+
    rect(1257,730,151,142,C.bg,C.cyan,5,.96)+rect(1421,730,151,142,C.bg,C.lime,5,.96)+
    rect(1320,755,26,47,'#ff932f','none',5)+rect(1325,745,16,10,C.white,'none',2)+text(1291,825,'Fanta',22,C.white,700)+tag(1272,842,'ГОТОВО',C.cyan,92)+
    rect(1484,755,26,47,'#d9b779','none',5)+rect(1489,745,16,10,C.white,'none',2)+text(1443,825,'Stroh 80',22,C.white,700)+tag(1437,842,'ГОТОВО',C.lime,92)+
    rect(1292,625,280,82,C.bg,'none',5,.9)+text(1313,687,'182',60,C.white,900)+text(1450,684,'км/ч',22,C.muted,700));

  const standings=[['1','Игрок 03','02:41.220','+94'],['2','Бот 01','02:42.016','+75'],['3','Игрок 01','02:42.386','+72'],['4','Игрок 02','02:43.010','+28'],['5','Бот 02','02:44.300','+12'],['6','Игрок 04','02:45.170','−8'],['7','Игрок 06','02:46.551','−17'],['8','Бот 03','02:48.792','−30'],['9','Игрок 05','02:50.180','−46'],['10','Бот 04','02:52.204','−61']];
  save('05-results','Результаты гонки',img('race',0,86,650,750)+rect(0,86,650,750,C.bg,'none',0,.77)+top()+
    tag(44,120,'ФИНИШ',C.lime,94)+text(42,298,'03',148,C.lime,900)+text(45,358,'НА ПОДИУМЕ',31,C.white,700)+text(46,399,'Трасса 01 · 02:42.386',19,C.muted)+
    line(44,440,585,440)+text(46,486,'РЕЙТИНГ',14,C.muted,700)+text(43,553,'1 352',58,C.white,700)+text(286,548,'+72',43,C.lime,700)+text(46,592,'Было 1 280 · Сила соперников учтена',17,C.muted)+
    text(46,651,'НАГРАДЫ',14,C.muted,700)+crystal(65,699,.47)+text(94,707,'+120',27,C.white,700)+text(260,707,'+340 опыта',27,C.white,700)+btn(44,759,541,'ЕЩЁ ЗАЕЗД')+
    text(690,145,'РЕЗУЛЬТАТЫ ЗАЕЗДА',25,C.white,700)+text(690,186,'6 игроков · 4 бота',16,C.muted)+text(732,237,'ГОНЩИК',12,C.muted,700)+text(1222,237,'ВРЕМЯ',12,C.muted,700)+text(1491,237,'РЕЙТИНГ',12,C.muted,700,'text-anchor="end"')+
    standings.map((p,i)=>rect(685,252+i*50,867,46,i===2?'#303b23':i%2?C.bg:C.panel,'none',3)+text(701,282+i*50,p[0],17,C.muted,700)+text(747,282+i*50,p[1],18,i===2?C.lime:C.white,700)+(p[1].startsWith('Бот')?tag(977,261+i*50,'БОТ',C.muted,62):'')+text(1222,282+i*50,p[2],18,C.white)+text(1491,282+i*50,p[3],20,p[3].startsWith('+')?C.lime:C.red,700,'text-anchor="end"')).join('')+btn(1190,772,362,'В ГЛАВНОЕ МЕНЮ',false)+foot());

  const mapNodes=[{x:150,y:472,n:'01',s:'ЗАВЕРШЁН'},{x:360,y:345,n:'02',s:'ДОСТУПЕН'},{x:600,y:500,n:'03',s:'ЗАКРЫТ'},{x:804,y:339,n:'04',s:'ЗАКРЫТ'}];
  save('06-campaign','Кампания и сюжетная карта',img('race',0,86,1090,756)+rect(0,86,1090,756,C.bg,'none',0,.67)+top('КАМПАНИЯ')+
    text(40,142,'КАРТА ЧЕМПИОНАТОВ',34,C.white,700)+tag(40,169,'ПРОЙДЕНО 1 / 4',C.cyan,162)+
    `<path d="M150 472 C200 330 290 290 360 345 S500 550 600 500 S700 300 804 339" fill="none" stroke="#192c25" stroke-width="18"/><path d="M150 472 C200 330 290 290 360 345 S500 550 600 500 S700 300 804 339" fill="none" stroke="#9cae98" stroke-width="3" stroke-dasharray="10 10"/>`+
    mapNodes.map((n,i)=>circle(n.x,n.y,i===1?40:30,C.bg,i<2?C.lime:C.muted,i===1?5:2)+text(n.x,n.y+9,n.n,i===1?28:23,i<2?C.lime:C.white,700,'text-anchor="middle"')+text(n.x,n.y+71,`Чемпионат ${n.n}`,19,C.white,700,'text-anchor="middle"')+text(n.x,n.y+95,n.s,11,i<2?C.lime:C.muted,700,'text-anchor="middle"')).join('')+
    rect(42,704,958,110,C.bg,C.line,4,.94)+text(63,739,'СЮЖЕТ',12,C.cyan,700)+text(63,775,'[Сюжетный эпизод: заглушка]',22,C.white,700)+
    rect(1050,86,550,760,C.bg)+text(1085,146,'Чемпионат 02',31,C.white,700)+text(1085,180,'0 / 3 гонки',17,C.muted)+line(1085,211,1558,211)+
    [['01','Трасса 02','3 круга'],['02','Трасса 03','3 круга'],['03','Финальный заезд','5 кругов']].map(([n,s,d],i)=>rect(1085,233+i*98,473,82,i===0?C.panel:C.bg,i===0?C.lime:C.line,3)+text(1104,283+i*98,n,26,i===0?C.lime:C.muted,700)+text(1162,269+i*98,s,20,C.white,700)+text(1162,295+i*98,d,15,C.muted)).join('')+
    text(1085,574,'НАГРАДЫ ЧЕМПИОНАТА',13,C.muted,700)+crystal(1105,616,.43)+text(1137,624,'600',25,C.white,700)+text(1256,624,'Деталь 03',21,C.cyan,700)+text(1085,685,'Соперник: [заглушка]',18,C.muted)+btn(1085,741,473,'НАЧАТЬ ЧЕМПИОНАТ')+foot());

  save('07-shop','Магазин и кристаллы',top('МАГАЗИН')+text(40,142,'МАГАЗИН',34,C.white,700)+
    ['Подборка','Машины','Детали','Косметика','Кристаллы'].map((s,i)=>text(41+i*177,194,s,17,i===0?C.lime:C.muted,700)).join('')+line(40,216,1560,216)+rect(40,212,114,4,C.lime)+
    rect(40,248,950,303,C.panel,C.line,4)+img('kart',363,250,623,300,'xMidYMid slice')+rect(40,248,580,303,'url(#shade)')+tag(62,268,'МАШИНА',C.cyan,111)+text(63,340,'Машина 02',34,C.white,700)+text(64,378,'Скорость · Мощность 460',17,C.muted)+text(64,416,'Характеристики',16,C.cyan,700)+btn(63,469,281,'1 800 КРИСТАЛЛОВ')+
    rect(1014,248,546,303,C.panel,C.line,4)+crystal(1456,348,2.25)+tag(1038,268,'СЛУЧАЙНАЯ НАГРАДА',C.lime,203)+text(1038,339,'Кристалл',32,C.white,700)+text(1038,369,'с наградой',32,C.white,700)+text(1038,407,'Машины · Детали · Косметика',17,C.muted)+text(1038,442,'Состав и вероятности  ↗',16,C.cyan,700)+btn(1038,471,232,'€ 2,99')+
    [['Деталь 04','Турбина · Мощность +35','850 кристаллов',C.cyan],['Окраска 01','Косметика','350 кристаллов',C.lime],['Эмоция 01','Косметика','200 кристаллов',C.red],['1 000 кристаллов','Валюта магазина','€ 7,99',C.cyan]].map(([name,detail,price,color],i)=>rect(40+i*386,576,362,238,C.panel,C.line,4)+(i===3?crystal(307+i*386,637,.85):circle(304+i*386,629,19,color))+text(62+i*386,631,name,23,C.white,700)+text(62+i*386,670,detail,16,C.muted)+btn(62+i*386,736,318,price,false)).join('')+foot('Баланс · История покупок'));

  save('08-friend-room','Комната друзей',top()+text(40,142,'КОМНАТА ДРУЗЕЙ',34,C.white,700)+tag(443,115,'6 / 10',C.cyan,89)+
    text(40,190,'Комната 01',20,C.white,700)+text(280,190,'По приглашению',17,C.muted)+btn(1284,112,276,'ПРИГЛАСИТЬ',false)+
    text(62,247,'УЧАСТНИКИ',13,C.muted,700)+['Игрок 01','Игрок 02','Игрок 03','Игрок 04','Бот 01','Бот 02','Свободное место','Свободное место','Свободное место','Свободное место'].map((s,i)=>rect(40,266+i*49,869,45,i%2?C.bg:C.panel,'none',3)+text(64,295+i*49,String(i+1).padStart(2,'0'),16,C.muted,700)+text(110,295+i*49,s,18,i>5?C.muted:C.white,600)+(i===0?tag(415,273+i*49,'ХОЗЯИН',C.lime,92):i===4||i===5?tag(415,273+i*49,'БОТ',C.muted,62):'')+text(877,295+i*49,i<6?'ГОТОВ':'+',i<6?12:22,i<6?C.cyan:C.muted,700,'text-anchor="end"')).join('')+
    img('race',952,235,608,251)+text(953,529,'Трасса 01',26,C.white,700)+text(1515,529,'›',28,C.cyan)+
    [['Круги','3'],['Свободные места','Заполнить ботами'],['Сложность ботов','По уровню лобби'],['Публичный рейтинг','Не меняется']].map(([a,b],i)=>text(954,578+i*42,a,17,C.muted)+text(1557,578+i*42,b,17,i===3?C.cyan:C.white,600,'text-anchor="end"')).join('')+
    btn(951,758,609,'НАЧАТЬ ГОНКУ')+btn(40,770,259,'ПОКИНУТЬ',false)+foot('Комната 01 · Европа · 34 мс'));

  const box=(x,y,w,h,n,title,rows,color=C.cyan)=>rect(x,y,w,h,C.panel,C.line,4)+tag(x+18,y+17,n,color,67)+text(x+18,y+80,title,23,C.white,700)+rows.map((s,i)=>text(x+18,y+115+i*27,s,16,C.muted)).join('');
  save('09-architecture','Архитектура: браузер, сервисы, гонка',
    text(40,64,'GNOM FIJI',23,C.lime,900)+text(40,128,'АРХИТЕКТУРА GODOT WEB',40,C.white,700)+tag(1088,92,'ТЕХНИЧЕСКИЕ РЕШЕНИЯ: ПРОЕКТ',C.cyan,465)+
    text(40,168,'Клиент отображает и предсказывает. Сервер подтверждает гонки, прогресс и покупки.',20,C.muted)+
    box(40,230,450,250,'01','Godot Web · Браузер',['Ввод: клавиатура / геймпад / touch','UI · локальное предсказание','Сетевое состояние · локализация','Не подтверждает награды и покупки'])+
    box(555,230,450,250,'02','Meta API',['Аккаунты · инвентарь · экономика','Рейтинг · подбор · комнаты','Выдача сессии и прав участия','Проверка идемпотентности операций'])+
    box(1070,230,490,250,'03','PostgreSQL',['Профиль · детали · рейтинг','Журнал покупок и выдачи наград','Транзакционные изменения баланса','Результаты заездов по race_id'])+
    box(40,570,450,230,'04','CDN · HTTPS',['Godot Web export · игровые ассеты','Версии клиента и каталога','Кэширование · доставка обновлений'])+
    box(555,570,450,230,'05','Godot Headless · Гонка',['Физика · предметы · боты','Контрольные точки · финиш','Серверный результат · reconnect'])+
    box(1070,570,231,230,'06','Allocator',['Пул серверов','Выдача worker','Масштабирование'])+
    box(1325,570,235,230,'07','Платежи',['Провайдер оплаты','Webhook → API','Проверка подписи'])+
    line(490,335,555,335,C.cyan,2)+text(507,320,'HTTPS',11,C.cyan,700)+line(1005,335,1070,335,C.cyan,2)+text(1015,320,'SQL',11,C.cyan,700)+
    line(265,480,265,570,C.cyan,2)+text(279,529,'Загрузка',13,C.cyan,700)+line(780,480,780,570,C.cyan,2)+text(794,515,'Сессия /',13,C.cyan,700)+text(794,540,'результат',13,C.cyan,700)+
    line(1005,699,1070,699,C.cyan,2)+
    `<path d="M966 480L966 507L1185 507L1185 570" fill="none" stroke="${C.cyan}" stroke-width="2"/>`+text(1070,530,'Выделить сервер',13,C.cyan,700)+
    `<path d="M1440 570L1440 548L925 548L925 480" fill="none" stroke="${C.red}" stroke-width="2"/>`+text(1356,532,'Webhook',13,C.red,700)+
    `<path d="M455 480L455 526L577 526L577 570" fill="none" stroke="${C.lime}" stroke-width="2"/>`+text(51,526,'WebRTC / измеренный WSS',15,C.lime,700)+
    text(40,855,'Транспорт и нагрузка подтверждаются сетевым прототипом.',15,C.muted)+
    text(1557,855,'09 / SYSTEM DESIGN',12,C.cyan,700,'text-anchor="end"'));

  const statePanel=(x,y,number,label,heading,rows,action,color=C.cyan)=>text(x,y-17,`${number} / ${label}`,13,C.muted,700)+rect(x,y,480,276,C.panel,C.line,6)+circle(x+32,y+33,8,color)+text(x+55,y+41,heading,21,C.white,700)+rows.map((s,i)=>text(x+23,y+89+i*28,s,17,C.muted)).join('')+btn(x+23,y+192,434,action,color===C.lime);
  save('10-interface-states','Ключевые состояния интерфейса',text(40,62,'GNOM FIJI',23,C.lime,900)+text(40,121,'СОСТОЯНИЯ И ДИАЛОГИ',38,C.white,700)+
    statePanel(40,188,'01','ГОСТЕВОЙ ПРОФИЛЬ','Сохраним твой прогресс',['Войди, чтобы участвовать в рейтинге','и совершать покупки. Гостевой прогресс','будет перенесён в аккаунт.'],'ВОЙТИ И ПРОДОЛЖИТЬ',C.lime)+
    statePanel(560,188,'02','ПОИСК СОПЕРНИКОВ','Подбираем соперников · 00:18',['Рейтинг: 1 280 · Мощность: 420','Ищем близких по результатам и сборке.','Свободные места займут боты.'],'ОТМЕНИТЬ ПОИСК',C.cyan)+
    statePanel(1080,188,'03','СОЕДИНЕНИЕ ПОТЕРЯНО','Восстанавливаем соединение',['Гонка продолжается на сервере.','Возвращаем тебя в текущий заезд.','Попытка 2 из 3'],'ВЕРНУТЬСЯ В МЕНЮ',C.red)+
    statePanel(40,532,'04','ПУСТОЙ ИНВЕНТАРЬ','Пока нет запасных деталей',['Открывай детали в чемпионатах','или выбирай их в магазине.','Установленные детали остаются на машине.'],'ОТКРЫТЬ МАГАЗИН',C.cyan)+
    statePanel(560,532,'05','ОПЛАТА В ОБРАБОТКЕ','Проверяем платёж',['Покупка: кристалл с наградой','Дождись подтверждения.','Повторно оплачивать не нужно.'],'К ИСТОРИИ ПОКУПОК',C.cyan)+
    statePanel(1080,532,'06','НАГРАДА ПОЛУЧЕНА','Твоя награда: Машина 02',['Кристалл открыт.','Машина добавлена в гараж.','Мощность машины: 460'],'ПЕРЕЙТИ В ГАРАЖ',C.lime)+
    text(40,860,'10 / UI STATES',12,C.cyan,700)+text(1560,860,'Текст и значения: проект интерфейса',13,C.muted,400,'text-anchor="end"'));

  for(const {id} of out){await sharp(path.join(root,'frames',`${id}.svg`)).png().toFile(path.join(root,'previews',`${id}.png`));}
  const tiles=await Promise.all(out.map(async({id},i)=>({input:await sharp(path.join(root,'previews',`${id}.png`)).resize(800,450).toBuffer(),left:(i%2)*800,top:Math.floor(i/2)*450})));
  await sharp({create:{width:1600,height:Math.ceil(out.length/2)*450,channels:3,background:C.bg}}).composite(tiles).png().toFile(path.join(root,'contact-sheet.png'));
  fs.writeFileSync(path.join(root,'index.html'),`<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>GNOM FIJI · Макеты</title><style>*{box-sizing:border-box}body{margin:0;background:#131715;color:#f5f7f4;font:16px Arial,sans-serif}header{padding:32px 4%;border-bottom:1px solid #3b4540}h1{font-size:28px;margin:0 0 12px;color:#e5ff58}nav{display:flex;flex-wrap:wrap;gap:10px 20px}a{color:#64e3db;text-decoration:none}main{padding:16px 4% 60px}section{padding-top:20px}h2{font-size:20px;font-weight:500}img{width:100%;height:auto;display:block;border:1px solid #3b4540}p{color:#a8b7af}html{scroll-behavior:smooth}</style><header><h1>GNOM FIJI: P.I.V.O RAUL RACING</h1><p>Концепт интерфейса · Desktop 1600 × 900 · Русский</p><nav>${out.map(({id,title})=>`<a href="#${id}">${esc(title)}</a>`).join('')}</nav></header><main>${out.map(({id,title})=>`<section id="${id}"><h2>${esc(title)}</h2><a href="frames/${id}.svg"><img src="previews/${id}.png" alt="${esc(title)}" width="1600" height="900"></a></section>`).join('')}</main></html>`);
  fs.writeFileSync(path.join(root,'manifest.json'),JSON.stringify({version:1,width:1600,height:900,locale:'ru',figmaPublished:false,frames:out},null,2)+'\n');
  console.log(`Created ${out.length} SVG frames, ${out.length} PNG previews, contact sheet and gallery.`);
}
main().catch(e=>{console.error(e);process.exit(1);});
