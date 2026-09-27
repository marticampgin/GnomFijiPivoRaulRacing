# GNOM FIJI: P.I.V.O RAUL RACING

Браузерная аркадная гонка на Godot: дрифт, боевые предметы, сборки машин, чемпионаты и онлайн до 10 участников. Русский интерфейс, десктоп сначала, мобильная архитектура предусмотрена.

## Текущее состояние

Подготовлены полный игровой дизайн, архитектура, roadmap и OpenSpec. Начата реализация технического прототипа: Godot Web, тестовая трасса, дрифт с ускорением, серверная физика, браузерная оболочка и local/test вход без Google. Десять принятых статических макетов доступны в [Figma](https://www.figma.com/design/OejURNEY5ZRhWWOBicFNYP?node-id=0-1).

Это ещё не первый полный игровой тест: нет предметов, ботов, рейтинга, кампании, Google-входа и платежей. Вместо исходных геометрических заглушек создан пробный 3D-набор по принятому арту: гном, бирюзовый кристальный карт, каменная трасса, замок и водопады. Детализация пока проще концепта, а маршрут остаётся техническим овалом. Сюжетные названия остаются заглушками. Проверенные возможности и ограничения фиксируются в [статусе поставки](docs/delivery.md).

| Артефакт | Назначение |
| --- | --- |
| [Игровой дизайн](docs/game-design.md) | Решения интервью, режимы, предметы, кандидат рейтинга, экранные состояния |
| [Архитектура](docs/architecture.md) | Godot Web/headless, сервер, данные, экономика, мобильная подготовка |
| [Roadmap](docs/roadmap.md) | Этапы и критерии готовности |
| [OpenSpec proposal](openspec/changes/design-gnom-fiji-racing/proposal.md) | Что и зачем создаётся |
| [OpenSpec design](openspec/changes/design-gnom-fiji-racing/design.md) | Решения и компромиссы реализации |
| [Задачи](openspec/changes/design-gnom-fiji-racing/tasks.md) | Проверяемый список будущей реализации |
| [Godot](game/README.md) | Запуск, управление и границы прототипа |
| [Toolchain](docs/toolchain.md) | Версии, контрольные суммы templates и воспроизводимый export |
| [Сетевой прототип](docs/network-prototype.md) | Сервер, билеты, prediction и проверки протокола |
| [Backend](backend/README.md) | Dev-вход, PostgreSQL, защита сессий и тесты |
| [Макеты](design/README.md) | Редактируемые экраны, иллюстрации и статус Figma |

## Локальный запуск

Нужны Node.js **24 LTS** и Godot **4.7.2** (`4.7.2.stable.official.ed1daf0bf`). `GODOT_BIN` можно задать абсолютным путём к бинарнику; по умолчанию используется `godot` из PATH. Установка export templates загружает официальный архив размером около 1.28 GB с проверкой SHA-256.

```sh
node scripts/setup-godot.mjs
npm --prefix backend ci
npm --prefix backend run build
node scripts/export-web.mjs
node scripts/dev.mjs --detach
```

Последняя команда печатает адрес игры, обычно `http://127.0.0.1:8787`. При занятом порте выбирается следующий. Запускаются loopback-only API, portable PostgreSQL и headless race worker. Google-конфигурация не требуется. Локальные данные и журналы находятся в игнорируемых `.local/` и `backend/.local/`.

```sh
node scripts/dev.mjs --stop
```

Для одиночной проверки физики достаточно открыть `game/project.godot` в Godot и запустить главную сцену. Этот native-режим не использует аккаунты и сетевую гонку.

## Разработка

Первый игровой тест: **одна трасса, три машины, шесть предметов и онлайн**. Полная цель: 10+ персонажей, 30+ машин, 10 трасс, 25+ предметов, 15+ модификаций.

Dev-профили используют настоящие серверные сессии, CSRF и отдельную локальную БД; публичное окружение не должно включать этот провайдер. Google-вход остаётся отдельной задачей. PostgreSQL хранит постоянные данные, физика работает в памяти Godot. Транспорт WS используется только на loopback: выбор production WebRTC/WSS ещё не завершён. Linux ARM64 на 4/8 ядрах является целью испытаний, не подтверждённым бюджетом одновременных игроков.

```sh
openspec status --change design-gnom-fiji-racing
openspec validate design-gnom-fiji-racing --strict
```

Продолжение реализации: `/opsx:apply design-gnom-fiji-racing`. Готовые документы и успешный cross-export не означают готовый продукт или проверенную серверную ёмкость.

## Источники и публикация

- [Исходная презентация](https://www.figma.com/design/JK4YNN8zKqhuZonVbDZ8YB/PPTX-to-Figma--Community-?node-id=2-546).
- [Опубликованные макеты и архитектурная схема в Figma](https://www.figma.com/design/OejURNEY5ZRhWWOBicFNYP?node-id=0-1). Векторная графика и 505 текстовых слоёв редактируемы; в Figma используется Arimo Regular/Bold вместо недоступного Arial. Исходные SVG с Arial не изменены.
- Репозиторий: [marticampgin/GnomFijiPivoRaulRacing](https://github.com/marticampgin/GnomFijiPivoRaulRacing). Публикация initial commit `20c55f8` подтверждена удалённым SHA.
- Подробности публикации и границы выполненных проверок: [delivery.md](docs/delivery.md).
