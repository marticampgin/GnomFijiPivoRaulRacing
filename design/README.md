# GNOM FIJI: P.I.V.O RAUL RACING: макеты и архитектура

Десять статических десктопных макетов размером 1600 x 900: восемь игровых экранов, схема архитектуры и лист ключевых состояний интерфейса. Интерфейс на русском языке. Это проект интерфейса, а не интерактивный прототип, работающая игра или библиотека production-компонентов. `index.html` содержит локальную галерею: каждая картинка ведёт на исходный SVG. `contact-sheet.png` показывает все экраны на одном листе.

## Статус публикации

Все десять листов опубликованы через Figma MCP в отдельном [Design-файле](https://www.figma.com/design/OejURNEY5ZRhWWOBicFNYP?node-id=0-1). Исходная презентация не изменялась. В Figma сохранены редактируемая векторная графика, восемь растровых изображений и 505 нативных редактируемых текстовых слоёв. Каждый лист отрендерен и проверен; геометрия текста проверена отдельно.

Arial недоступен в подключённом Figma-окружении, поэтому текст перенесён с Arimo Regular/Bold. Три символа стрелки вверх-вправо заменены редактируемыми векторными иконками Lucide ArrowUpRight: иначе Figma показывала их цветными emoji. Это небольшие корректировки переноса, а не обещание полного пиксельного совпадения. Исходные SVG сохраняют Arial с запасным sans-serif и не изменены. Они самодостаточны: игровой арт встроен как растровые изображения, текст и фигуры остаются векторными элементами.

Макеты приняты пользователем 2026-09-26. Идентификаторы листов и результаты проверки сохранены в `figma-publication.json`. Это запись проверенной публикации, не автоматическая синхронизация с Figma. Повторный запуск `generate.cjs` сбрасывает `manifest.json` в `figmaPublished: false`: новую генерацию нужно сверить и опубликовать отдельно.

## Содержание экранов

1. [Главный экран](https://www.figma.com/design/OejURNEY5ZRhWWOBicFNYP?node-id=3-2): вход в рейтинговый заезд, продолжение кампании, комната друзей, выбранная сборка.
2. [Гараж](https://www.figma.com/design/OejURNEY5ZRhWWOBicFNYP?node-id=3-22): скорость, ускорение, управляемость, дрифт, прочность, уровни деталей, мощность для подбора.
3. [Рейтинговое лобби](https://www.figma.com/design/OejURNEY5ZRhWWOBicFNYP?node-id=3-60): игроки и явно отмеченные боты, рейтинг, мощность, обратный отсчёт.
4. [Гоночный HUD](https://www.figma.com/design/OejURNEY5ZRhWWOBicFNYP?node-id=3-101): позиция, круги, время, мини-карта, прочность, скорость, ускорение за дрифт, два сразу доступных предмета.
5. [Результаты](https://www.figma.com/design/OejURNEY5ZRhWWOBicFNYP?node-id=3-130): повышение и снижение рейтинга с учётом соперников, равные правила для ботов и людей, награды.
6. [Кампания](https://www.figma.com/design/OejURNEY5ZRhWWOBicFNYP?node-id=3-166): карта чемпионатов, серия из трёх заездов, доступные и закрытые этапы. Сюжет и финальный соперник остаются явными заглушками.
7. [Магазин](https://www.figma.com/design/OejURNEY5ZRhWWOBicFNYP?node-id=3-198): прямые продажи машин и деталей, категории косметики, платные случайные кристаллы с игровыми предметами, вход в состав и вероятности, валюта.
8. [Комната друзей](https://www.figma.com/design/OejURNEY5ZRhWWOBicFNYP?node-id=3-239): приглашение, список участников, боты, трасса и настройки. Публичный рейтинг не меняется.
9. [Архитектура](https://www.figma.com/design/OejURNEY5ZRhWWOBicFNYP?node-id=3-269): проект Godot Web клиента, CDN, авторитетных гоночных серверов, метасервисов, журнала транзакций, выделения серверов и платёжного провайдера.
10. [Состояния](https://www.figma.com/design/OejURNEY5ZRhWWOBicFNYP?node-id=3-294): вход гостя с переносом прогресса, поиск соперников, потеря соединения, пустой инвентарь, обработка оплаты и подтверждённая выдача машины из кристалла. Полный набор состояний компонентов остаётся задачей реализации.

## Решения и демонстрационные значения

Значения на экранах демонстрационные: они не утверждают баланс или коммерческие условия. Рейтинги, изменения очков, мощность машин, награды, уровни деталей, баланс валют и цены требуют отдельной настройки. Полная таблица вероятностей случайного кристалла, подтверждение покупки, страницы платёжного провайдера и возвраты не изображены: их необходимо спроектировать до коммерческого запуска. Вероятности выпадения в макетах не выдуманы.

Пользователь сохранил реальные названия предметов из презентации, поэтому HUD использует Fanta и Stroh 80. Новые гонщики, машины, чемпионаты и трассы обозначены нейтральными номерами. Сгенерированный арт является визуальным предложением, а не точным воспроизведением существующих персонажей или финальными игровыми моделями. Гном в красном колпаке и бирюзовый карт являются рабочими концептами.

Первый релиз рассчитан на десктоп. Архитектура должна учитывать масштабирование интерфейса, клавиатуру и геймпад, абстрактные действия ввода, локализацию и варианты раскладки под touch. Макеты изображают только десктоп: проверка мобильного игрового интерфейса не проводилась.

## Повторная генерация

Команды из корня проекта с установленным локальным runtime:

```sh
NODE_PATH=/Users/sergejssokolovs/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules /Users/sergejssokolovs/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node design/generate.cjs
NODE_PATH=/Users/sergejssokolovs/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules /Users/sergejssokolovs/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node design/verify.cjs
```

Генератор использует пакет `sharp`; проверка использует `playwright` и установленный Chromium. На другой машине установите эти зависимости в отдельное окружение и задайте соответствующий `NODE_PATH`. Генератор встраивает JPEG-копии исходных PNG в SVG и создаёт PNG-превью, manifest и статическую галерею. Арт создан встроенным imagegen, без API-ключа и без CLI-режима.

## Происхождение арта и промпты

`assets/race-concept.png` и `assets/kart-concept.png` сгенерированы для этого проекта 2026-09-26 встроенным imagegen. JPEG являются копиями для упаковки макетов. Визуальное направление основано на презентации: яркий пейзаж, замок и водопад, гномы-гонщики и кристальные двигатели. Это AI-концепты, не скриншоты работающего Godot. Оригинальные промпты сохранены ниже на английском.

Промпт гонки:

> Use case: stylized-concept. Asset type: full-bleed gameplay concept backdrop for a desktop fantasy combat kart-racing game, 16:9 wide, ideally 2048x1152. A vividly colorful, premium stylized 3D game screenshot with a third-person chase camera directly behind a chunky low-slung racing kart piloted by a fantasy gnome with a red pointed cap, small driver. Main kart is center-bottom viewed from behind, broad fat tires, teal chassis, metal fenders and a cyan crystal engine with purple highlights, two subtle bright exhaust trails as it drifts around a wide paved race track. Three rival karts visible well ahead. Actual track occupies lower two thirds with readable perspective. Lush saturated green trees, distant monumental stone castle, cliff waterfall and turquoise water off track, blue daytime sky. Crisp believable 3D game art, gorgeous materials, stylized detailed foliage, joyful fast arcade action. The camera must show the whole main kart with all wheels inside frame. Rich leaf green and cyan, warm sunlight, bright blue sky, accents hot coral. No text, no logos, no UI, no HUD, no border, no watermark. Side edges and sky leave useful clear space for later overlay HUD. Not a drawing or painting; looks like beautifully art-directed playable 3D game.

Промпт карта:

> Use case: stylized-concept. Asset type: vehicle selection studio image for fantasy combat kart racing game. Wide 16:9 3D render. One beautifully detailed chunky compact racing kart, three-quarter front-left view, entire vehicle in frame, pointing slightly left, positioned centrally with wide empty charcoal space surrounding. Teal enamel body panels, brushed metal and black chassis, oversized knobby rubber tires, warm brass suspension struts and round headlamps, exposed floating cyan crystal reactor behind seat with very restrained lavender energy, fantasy mechanical design. Tiny stout gnome driver in red pointed cap sits visibly in cockpit, not dominant, expressive pointed nose and white beard. Crisp premium stylized game 3D render, realistic miniature materials with slight wear, strong studio softbox highlights. Background simple flat very dark neutral charcoal gray near #151917, with soft grounding shadow beneath kart. Bright inspectable fully lit vehicle, no dramatic obscuring fog. No text, no UI, no logos, no watermark, no border. Kart takes 75% of width and 70% height. This is a fictional racing vehicle, playful modern arcade style.

## Проверка

Все десять локальных листов отрисованы в PNG через Sharp/librsvg и визуально проверены. Playwright проверил границы текстовых элементов: выходов за холст нет. Все картинки локальной галереи загрузились; галерея не имеет горизонтального переполнения при ширине 390 px. Это проверка галереи, не мобильного игрового HUD. Результаты записаны в `verification.json`; повторная проверка доступна в `verify.cjs`.

После переноса через Figma MCP успешно отрендерены все десять листов, проверены общий контактный лист и границы нативного текста; HUD дополнительно проверен визуально. Публикация подтверждена ссылками выше. Макеты не подтверждают работу движка, платежей или мультиплеера.
