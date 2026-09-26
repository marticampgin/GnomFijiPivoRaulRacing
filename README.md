# GNOM FIJI: P.I.V.O RAUL RACING

Браузерная аркадная гонка на Godot: дрифт, боевые предметы, сборки машин, чемпионаты и онлайн до 10 участников. Русский интерфейс, десктоп сначала, мобильная архитектура предусмотрена.

## Текущее состояние

Подготовлены полный игровой дизайн, архитектура, roadmap, OpenSpec и минимальная основа Godot. Десять статических десктопных макетов опубликованы в [Figma](https://www.figma.com/design/OejURNEY5ZRhWWOBicFNYP?node-id=0-1), initial commit опубликован в GitHub. Это не интерактивный прототип и не библиотека production-компонентов. Игровая гонка, сетевые сервисы, аккаунты и реальные платежи ещё не реализованы. Новые сюжетные названия остаются заглушками.

| Артефакт | Назначение |
| --- | --- |
| [Игровой дизайн](docs/game-design.md) | Решения интервью, режимы, предметы, кандидат рейтинга, экранные состояния |
| [Архитектура](docs/architecture.md) | Godot Web/headless, сервер, данные, экономика, мобильная подготовка |
| [Roadmap](docs/roadmap.md) | Этапы и критерии готовности |
| [OpenSpec proposal](openspec/changes/design-gnom-fiji-racing/proposal.md) | Что и зачем создаётся |
| [OpenSpec design](openspec/changes/design-gnom-fiji-racing/design.md) | Решения и компромиссы реализации |
| [Задачи](openspec/changes/design-gnom-fiji-racing/tasks.md) | Проверяемый список будущей реализации |
| [Godot foundation](game/README.md) | Запуск, Web export и результаты проверки |
| [Макеты](design/README.md) | Редактируемые экраны, иллюстрации и статус Figma |

## Запуск основы

Открыть `game/project.godot` в Godot **4.7.2** и запустить проект. Проверенный бинарный build: `4.7.2.stable.official.ed1daf0bf`.

```sh
godot --editor --path game
godot --headless --editor --path game --import
godot --headless --path game --quit-after 2
```

Для Web export установить соответствующие export templates; текущая проверка headless не подтверждает браузерную производительность. Настроен Compatibility, GDScript и single-thread Web preset.

## Разработка

Первый игровой тест: **одна трасса, три машины, шесть предметов и онлайн**. Полная цель: 10+ персонажей, 30+ машин, 10 трасс, 25+ предметов, 15+ модификаций.

В архитектуре предусмотрены Google-вход и отдельный local/test вход без Google OAuth. Оба создают обычную игровую сессию, но dev-профили недоступны в публичном окружении. Реализация авторизации ещё впереди; сейчас Google configuration для запуска основы не нужна. PostgreSQL хранит постоянные данные, физика работает в памяти Godot. Linux ARM64 на 4/8 ядрах является целью испытаний, не подтверждённым бюджетом одновременных игроков.

```sh
openspec status --change design-gnom-fiji-racing
openspec validate design-gnom-fiji-racing --strict
```

Для реализации использовать `/opsx:apply` с change `design-gnom-fiji-racing`. Готовые документы не означают готовый продукт.

## Источники и публикация

- [Исходная презентация](https://www.figma.com/design/JK4YNN8zKqhuZonVbDZ8YB/PPTX-to-Figma--Community-?node-id=2-546).
- [Опубликованные макеты и архитектурная схема в Figma](https://www.figma.com/design/OejURNEY5ZRhWWOBicFNYP?node-id=0-1). Векторная графика и 505 текстовых слоёв редактируемы; в Figma используется Arimo Regular/Bold вместо недоступного Arial. Исходные SVG с Arial не изменены.
- Репозиторий: [marticampgin/GnomFijiPivoRaulRacing](https://github.com/marticampgin/GnomFijiPivoRaulRacing). Публикация initial commit `20c55f8` подтверждена удалённым SHA.
- Подробности публикации и границы выполненных проверок: [delivery.md](docs/delivery.md).
