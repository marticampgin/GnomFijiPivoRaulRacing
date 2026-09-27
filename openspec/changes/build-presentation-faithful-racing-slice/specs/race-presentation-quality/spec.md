## ADDED Requirements

### Requirement: Drivable camera and truthful HUD
Обычная chase-камера SHALL сохранять читаемость карта и ближайшего направления дороги на всём маршруте, поддерживать look-back и сброс соответствующего input при потере фокуса/меню. Она MUST NOT проникать в окружение. HUD SHALL следовать иерархии принятого Figma и отображать только реализованные состояния из фактических данных; отсутствующие предметы/прочность/рейтинг/награды MUST NOT имитироваться.

#### Scenario: Camera follows a crest and a turn
- **WHEN** игрок проходит подъём, гребень и лесной поворот
- **THEN** дорога впереди и машина остаются читаемы, камера не оказывается внутри скалы/барьера и HUD не перекрывает контрольный коридор

#### Scenario: Focus changes during look-back
- **WHEN** игрок теряет фокус или открывает меню с удерживаемым look-back
- **THEN** действие сбрасывается и возврат в гонку не оставляет камеру в нежелательном состоянии

#### Scenario: Unsupported gameplay features are absent
- **WHEN** визуальный срез запускается без предметов, рейтинга или экономики
- **THEN** HUD/результат не показывают фиктивные значения или неработающие активные элементы этих систем
- **AND** круги, место, скорость, время, drift/boost и сеть берутся из действующего состояния гонки

### Requirement: Web-compatible lighting and readable effects
Материалы, свет, вода и эффекты SHALL работать в закреплённой Godot Web Compatibility-сборке. Drift/boost эффекты SHALL соответствовать состоянию игры и сохранять обзор. Reduced-effects режим SHALL уменьшать вспышки, частицы и тряску без изменения управления или симуляции.

#### Scenario: Dense visual scene renders in browser
- **WHEN** машина с активным boost проходит у воды и листвы
- **THEN** материалы/текстуры/анимации отображаются без shader/runtime ошибок и непрозрачных следов, закрывающих дорогу
- **AND** дневной свет сохраняет читаемость кристалла, дорожных границ и соперников

#### Scenario: Reduced effects is selected
- **WHEN** игрок включает reduced-effects
- **THEN** интенсивность мешающих обзору эффектов снижается, а trajectory, drift charge и boost timing не меняются

### Requirement: Quality profiles preserve the racing contract
Standard и Low SHALL разделять renderer/asset budgets, но MUST использовать идентичные route, collision, visibility of gameplay boundaries и server rules. Упрощения SHALL сохранять характерный силуэт героя, кристалл, дорогу и ориентиры. Layout на мобильных размерах MUST NOT объявляться поддержкой touch или подтверждённой мобильной производительностью.

#### Scenario: Quality changes during a test race
- **WHEN** выбирается другой профиль качества
- **THEN** изменяются разрешение/LOD/тени/декорации/VFX согласно профилю, но simulation identity, checkpoint и прогресс сохраняются
- **AND** оба профиля проходят функциональные route tests

### Requirement: Measured budgets on a declared target
До окончательного производства ассетов SHALL быть заполнен и принят версионированный budget manifest с устройством, браузером, разрешением, профилем, сценарием и численными лимитами frame-time/load/transfer/memory для доступных метрик. Измерение SHALL включать p50/p95/p99 после прогрева, cold load отдельно и три полных круга. Цель около 60 FPS MUST NOT выдаваться за достигнутую без результатов.

#### Scenario: Performance gate is evaluated
- **WHEN** release Web-build проверяется по фиксированному manifest
- **THEN** отчёт содержит версии, условия, сырые замеры и pass/fail для каждого согласованного лимита
- **AND** unavailable metric явно отмечена, отсутствующий manifest или непрошедший лимит оставляет gate открытым
- **AND** пределы не изменяются задним числом без отдельного согласования

#### Scenario: Ten visible karts are profiled
- **WHEN** используется fixture с десятью визуальными картами на плотном участке
- **THEN** результат маркируется как rendering workload, а не тест десяти сетевых участников, ботов или вместимости ARM-сервера

### Requirement: Reproducible browser and network acceptance
Принимаемый пакет SHALL проходить реальные Web-рендеры на 1600x900, 390x844 и 844x390, проверку непустого меняющегося canvas, границ HUD и ошибок. Две браузерные сессии SHALL сохранять работающий сетевой цикл с авторитетным финишем, recovery, reconnect и freeze/resume на новом маршруте. Headless geometry tests MUST дополняться рендером, а не заменять его.

#### Scenario: Responsive views are rendered
- **WHEN** release-build загружается в каждом контрольном viewport и машина движется
- **THEN** canvas непустой и меняется, assets загружены, текст/контролы не выходят за границы и не перекрываются
- **AND** сохранены реальные screenshots, параметры запуска и сообщения ошибок

#### Scenario: Two clients finish and recover
- **WHEN** два dev-профиля проходят сетевой заезд с дрифтом/boost, возвратом и приостановкой одной вкладки
- **THEN** сервер сохраняет корректные круги/места и однократный финиш, а возобновлённый клиент согласуется с ним
- **AND** текущие protocol/auth/client regression tests не ослаблены ради нового визуального набора

### Requirement: Delivery separates completed and deferred scope
Отчёт этого change SHALL отдельно фиксировать принятые визуальные изменения, функциональные результаты, бюджетные измерения и незавершённые системы. Родительские tasks MUST закрываться только после проверки полного собственного условия, не по одному факту завершения этого среза.

#### Scenario: Visual slice is delivered
- **WHEN** подготавливается итоговая поставка
- **THEN** она содержит ссылку на рабочую Web-сборку и доказательства проверки
- **AND** не объявляет готовыми предметы/ботов/рейтинг/Google OAuth/магазин/ARM/mobile, не выполненные этим этапом
- **AND** сохраняет следующий пакет полного игрового теста в общем roadmap
