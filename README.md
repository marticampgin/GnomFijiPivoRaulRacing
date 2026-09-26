# GNOM FIJI: P.I.V.O RAUL RACING

Браузерная аркадная гонка на Godot: дрифт, боевые предметы, сборки машин, чемпионаты и онлайн до 10 участников. Русский интерфейс, десктоп сначала, мобильная архитектура предусмотрена.

## Текущее состояние

Подготовлены полный игровой дизайн, архитектура, roadmap, OpenSpec и минимальная основа Godot. Игровая гонка, сетевые сервисы, аккаунты и реальные платежи ещё не реализованы. Новые сюжетные названия остаются заглушками.

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

```sh
openspec status --change design-gnom-fiji-racing
openspec validate design-gnom-fiji-racing --strict
```

Для реализации использовать `/opsx:apply` с change `design-gnom-fiji-racing`. Готовые документы не означают готовый продукт.

## Источники и публикация

- [Исходная презентация](https://www.figma.com/design/JK4YNN8zKqhuZonVbDZ8YB/PPTX-to-Figma--Community-?node-id=2-546).
- Целевой репозиторий: [marticampgin/GnomFijiPivoRaulRacing](https://github.com/marticampgin/GnomFijiPivoRaulRacing).
- Статус удалённой публикации фиксируется в [delivery.md](docs/delivery.md); локальные файлы не доказывают, что они уже появились в GitHub или Figma.
