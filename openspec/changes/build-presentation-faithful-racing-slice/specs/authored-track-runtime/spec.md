## ADDED Requirements

### Requirement: One versioned spatial track definition
Авторская трасса SHALL иметь один источник route/samples, высоты, ширины, surfaces, gates, стартовых мест, recovery anchors и допустимого коридора. Дорога, collision bake, AI-направляющие и миникарта SHALL выводиться из него. Некорректные данные MUST отклоняться до запуска гонки. Identity SHALL разделять simulation hash/revision и art revision.

#### Scenario: Valid track is baked
- **WHEN** замкнутый маршрут собран в runtime-пакет
- **THEN** samples конечны, длина монотонна, сегменты ненулевые, gates уникальны и упорядочены
- **AND** десять стартовых мест и все recovery anchors проходят проверку опоры/зазора до барьеров
- **AND** collision и minimap manifests ссылаются на тот же track identity

#### Scenario: Track data is malformed
- **WHEN** bake обнаруживает неконечные координаты, нулевой сегмент, неподдержанную неоднозначную топологию или invalid anchor
- **THEN** сборка завершается диагностикой конкретного элемента и не выпускает принимаемый simulation package

#### Scenario: Only scenery changes
- **WHEN** меняются только визуальные деревья, текстуры или декорации без физического влияния
- **THEN** art revision изменяется без изменения simulation hash
- **AND** изменение collision/gates/recovery/surfaces обязательно изменяет simulation identity

### Requirement: Shared drivable road and isolated server resources
Клиентская prediction/replay и сервер SHALL использовать один simulation bake и проверяемые физические настройки. Рельефная трасса MUST проходиться существующим контроллером с мировой гравитацией, включая подъём, спуск, гребень и поворот. Headless worker MUST NOT создавать или загружать графический набор через зависимости simulation-сцены.

#### Scenario: Client and worker load the same route
- **WHEN** обе стороны загружают один track package
- **THEN** формы и transforms коллизий совпадают, hash совпадает и точки поверхности согласованы с видимой дорогой
- **AND** worker не содержит render nodes, visual materials/textures, cameras, rigs или VFX

#### Scenario: Vehicle drives through elevation changes
- **WHEN** машина проходит все уклоны и повороты в рабочем диапазоне скоростей
- **THEN** она не проваливается, не застревает на стыках и не получает непредусмотренный boost/скачок от переходов поверхности
- **AND** видимые шины/кузов согласованы с gameplay collider в проверенных контактах со стеной и дорогой

### Requirement: Directed authoritative checkpoint progression
Только сервер SHALL подтверждать ожидаемые checkpoints по направленному swept-пересечению их 3D-gates. Круг MUST засчитываться ровно один раз после обязательной последовательности и правильного пересечения финиша. Стояние, движение назад, повторный gate, off-track shortcut и teleport MUST NOT создавать прогресс.

Сервер SHALL отслеживать валидность разрешённого коридора на всём интервале между gates, с явно заданным допуском обочины. Выход за этот коридор MUST блокировать подтверждение следующего gate до recovery к разрешённому anchor и повторного валидного прохождения интервала.

#### Scenario: Fast valid crossing
- **WHEN** машина проходит gate между двумя server ticks, включая последовательность нескольких gates в одном допустимом swept-отрезке
- **THEN** сервер подтверждает пересечения в порядке движения без потери или двойного зачёта

#### Scenario: Invalid crossing or shortcut
- **WHEN** машина пересекает gate назад, вне его ширины/высоты, пропускает ожидаемый gate или проходит под мостом рядом с gate верхней дороги
- **THEN** ожидаемый checkpoint и число кругов не продвигаются

#### Scenario: Shortcut reaches the expected gate
- **WHEN** машина покидает разрешённый коридор между соседними gates и затем пересекает правильный следующий gate в нужном направлении
- **THEN** следующий checkpoint не засчитывается и возвращение на дорогу не стирает нарушение
- **AND** server recovery позволяет пройти интервал заново без выдачи прогресса за срез

#### Scenario: Finish line is revisited
- **WHEN** машина пересекает финиш повторно без полного цикла gates или сервер уже зарегистрировал окончательный финиш
- **THEN** новый круг/повторный результат не выдаётся

### Requirement: Progress projection respects confirmed route interval
Место в гонке SHALL рассчитываться по завершённым кругам, подтверждённому checkpoint и ограниченной пространственной проекции внутри разрешённого интервала. Ближайший по XZ или Euclidean distance участок MUST NOT самостоятельно менять checkpoint или переносить прогресс вперёд.

#### Scenario: Nearby road sections compete for nearest point
- **WHEN** автомобиль расположен возле соседнего поворота или над/под другим участком
- **THEN** standings используют подтверждённый interval и высоту/направление, а не перескакивают на соседнюю часть маршрута
- **AND** ни одна projection не подтверждает следующий checkpoint

### Requirement: Safe recovery without gaining progress
Ручной и автоматический recovery SHALL выбирать последний разрешённый anchor и сохранять число кругов/ожидаемый gate. Он MUST помечать discontinuity, очищать движение/drift/boost и устаревшие команды согласно epoch-контракту. Off-track detection SHALL использовать геометрию маршрута/kill volumes, не одну мировую высоту.

#### Scenario: Vehicle falls near an elevated section
- **WHEN** машина выходит в запрещённый объём у моста, скалы или низкого участка
- **THEN** сервер возвращает её на безопасный разрешённый anchor без переноса на более поздний checkpoint
- **AND** клиент получает новую авторитетную позицию и не воспроизводит команды до recovery

#### Scenario: Recovery crosses gates in space
- **WHEN** прямая между старой позицией и recovery anchor пересекает один или несколько gates
- **THEN** это перемещение не засчитывает gates, круг или финиш

### Requirement: Track compatibility checked before racing
Launch descriptor, race ticket и hello/welcome SHALL связывать гонку с доверенным track identity и protocol schema. Worker MUST отклонять несовместимый клиент до допуска к гонке. Проверка hash MUST NOT заменять серверную проверку движения.

Версии wire/ticket protocol, vehicle-state schema и track schema SHALL проверяться раздельно по явной совместимости. Изменение protocol version MUST NOT ошибочно отклонять корректное состояние неизменённой vehicle-state schema.

#### Scenario: Stale oval client connects
- **WHEN** клиент предъявляет старый protocol или иной simulation hash
- **THEN** он не получает управление участником новой трассы и видит понятное требование обновления

#### Scenario: Compatible reconnect
- **WHEN** клиент с тем же simulation package возвращается в действующую гонку
- **THEN** он получает текущие server checkpoint/lap/recovery state и продолжает в рамках существующей reconnect-политики

#### Scenario: Protocol version changes while vehicle-state schema stays valid
- **WHEN** корректный vehicle snapshot проходит serialize/validate/deserialize через обновлённый protocol
- **THEN** его state schema проверяется по собственной версии и round-trip сохраняет допустимые значения
- **AND** snapshot с неподдерживаемой state schema отклоняется явно

### Requirement: Minimap and guide data follow the authored route
HTML HUD SHALL получать polyline, bounds и world-to-map из track descriptor и отображать фактическую форму трассы, старт и участников. Runtime data SHALL предоставлять последовательные направление/ширину/кривизну для будущего AI. Эти данные MUST NOT называться работающими ботами.

#### Scenario: Authored route replaces the oval
- **WHEN** HUD получает descriptor нового маршрута
- **THEN** карта и маркеры соответствуют его форме и координатам без захардкоженных радиусов 62/42
- **AND** тестовые точки всех четырёх участков отображаются в ожидаемых местах

#### Scenario: AI guide is validated
- **WHEN** проверяется сгенерированный route guide
- **THEN** он непрерывен, соответствует направлению круга и остаётся внутри допустимой дорожной ширины
