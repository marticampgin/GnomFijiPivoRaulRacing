# GNOM FIJI: P.I.V.O RAUL RACING: макеты и архитектура

Десять SVG-макетов размером 1600 x 900: восемь игровых экранов, схема архитектуры и лист ключевых состояний интерфейса. Интерфейс на русском языке. Это проект интерфейса, а не работающая игра. `index.html` содержит локальную галерею: каждая картинка ведёт на исходный SVG. `contact-sheet.png` показывает все экраны на одном листе.

## Статус публикации

В Figma эти файлы НЕ опубликованы. После восстановления подключения можно импортировать SVG из `frames/` на страницу Figma Design. В исходных SVG текст и фигуры остаются векторными элементами; игровой арт встроен как растровые изображения. Шрифт Arial с запасным sans-serif. При импорте Figma может преобразовать текст в контуры: в этом случае строки из генератора позволяют восстановить нативные текстовые слои. Редактируемость нативных слоёв в Figma пока не проверена. SVG самодостаточны и не требуют внешних картинок.

## Содержание экранов

1. Главный экран: вход в рейтинговый заезд, продолжение кампании, комната друзей, выбранная сборка.
2. Гараж: скорость, ускорение, управляемость, дрифт, прочность, уровни деталей, мощность для подбора.
3. Рейтинговое лобби: игроки и явно отмеченные боты, рейтинг, мощность, обратный отсчёт.
4. Гоночный HUD: позиция, круги, время, мини-карта, прочность, скорость, ускорение за дрифт, два сразу доступных предмета.
5. Результаты: повышение и снижение рейтинга с учётом соперников, равные правила для ботов и людей, награды.
6. Кампания: карта чемпионатов, серия из трёх заездов, доступные и закрытые этапы. Сюжет и финальный соперник остаются явными заглушками.
7. Магазин: прямые продажи машин и деталей, категории косметики, платные случайные кристаллы с игровыми предметами, вход в состав и вероятности, валюта.
8. Комната друзей: приглашение, список участников, боты, трасса и настройки. Публичный рейтинг не меняется.
9. Архитектура: проект Godot Web клиента, CDN, авторитетных гоночных серверов, метасервисов, журнала транзакций, выделения серверов и платёжного провайдера.
10. Состояния: вход гостя с переносом прогресса, поиск соперников, потеря соединения, пустой инвентарь, обработка оплаты и подтверждённая выдача машины из кристалла. Полный набор состояний компонентов остаётся задачей реализации.

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

Все десять листов отрисованы в PNG через Sharp/librsvg и визуально проверены. Playwright проверил границы текстовых элементов: выходов за холст нет. Все картинки локальной галереи загрузились; галерея не имеет горизонтального переполнения при ширине 390 px. Это проверка галереи, не мобильного игрового HUD. Результаты записаны в `verification.json`; повторная проверка доступна в `verify.cjs`. Макеты не подтверждают работу движка, платежей, мультиплеера или публикацию в Figma.
