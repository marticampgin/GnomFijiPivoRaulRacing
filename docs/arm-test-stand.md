# Закрытый Linux ARM64 стенд

Статус: подготовленный scaffold, **не проверенный запуск на Linux ARM64**. Docker на текущем компьютере отсутствует. Здесь не арендован сервер, не установлен системный софт и не измерена вместимость 4/8-ядерного хоста. Задача OpenSpec 2.7 остаётся открытой.

## Состав и границы

- `infra/arm/compose.yaml`: PostgreSQL 18.6, Node.js 24.21.0 API и Godot 4.7.2 ARM64 headless worker.
- `stand.mjs init` получает digests официальных multi-arch образов и сохраняет immutable references. Следующие запуски сохраняют lock и секреты. Dockerfiles требуют ARM64; API/DB образы проверяются на наличие Linux ARM64 и AMD64 в manifest index, но worker намеренно только ARM64.
- API использует `DEPLOYMENT_ENV=test`, отдельный database marker, dev-профили и реальные серверные сессии. Google и платежи не нужны. Это **не public staging и не production**.
- Linux host networking нужен для неизменённого loopback-контракта API и worker. Все три сервиса слушают исключительно `127.0.0.1`: API 8787, race 9080, SQL 55432. Никаких `0.0.0.0`, published ports или public reverse proxy.
- API и worker работают непривилегированными пользователями, с read-only filesystem, временным `/tmp`, снятыми capabilities и ограничениями ресурсов. SQL хранит только тестовые данные в отдельном volume. Стендовый SQL owner не является production-моделью ролей.

Host networking даёт контейнеру доступ к сетевому пространству хоста. Использовать только на собственном выделенном тестовом окружении, без production-секретов и данных. [Docker networking](https://docs.docker.com/compose/how-tos/networking/)

## Предпосылки

Нужны уже доступные Linux ARM64 host, Docker Engine с Compose v2, локальный Docker Unix socket и Node.js 24. У экспортированного бинарника ELF указывает GNU/Linux 5.15; запуск и совместимость с выбранным kernel нужно подтвердить на хосте. Скрипты ничего не устанавливают. Нативный ARM обязателен: QEMU, Docker Desktop на macOS и cross-export не заменяют замер Linux-сервера. Выбор Docker endpoint учитывает приоритет `DOCKER_CONTEXT` над `DOCKER_HOST`; удалённые TCP/SSH endpoints запрещены также для status/logs/down и monitor.

Запускать из корня репозитория. Сначала собрать актуальные Web и ARM артефакты закреплённым Godot и шаблонами из `tooling/godot.json`:

```sh
node scripts/setup-godot.mjs --check
export GODOT_BIN=/absolute/path/to/Godot
node scripts/export-web.mjs
mkdir -p build/server
"$GODOT_BIN" --headless --path game --export-release "Linux ARM64 Server" ../build/server/gnom-racing.arm64
```

Для последней команды `GODOT_BIN` должен быть задан в окружении shell. Web-экспорт можно сделать на другом компьютере и передать весь `build/web/`, `build/server/gnom-racing.arm64` и соответствующий `gnom-racing.pck` на ARM-хост вместе с тем же исходным кодом. Не смешивать бинарник/PCK и commit разных сборок.

## Запуск и доступ

```sh
node infra/arm/stand.mjs init
node infra/arm/stand.mjs check
node infra/arm/stand.mjs up
node infra/arm/stand.mjs status
```

`init` связывается только с публичным Docker registry для фиксации manifest digests; контейнеры не запускает. В `.local/stand.env` создаёт независимые 256-битные секреты с правами 0600 внутри каталога 0700. Файлы ignored, значения не печатаются. Docker-оператор может читать environment контейнера, поэтому доступ к Docker должен оставаться доверенным. Не публиковать `docker compose config` без `--quiet` и не включать `.local/` в отчёты/коммиты.

`check` проверяет native architecture хоста/daemon, pinned images, права/формат секретов, ARM64 ELF header, наличие непустых сборок и Compose schema. SHA-256 артефактов и сведения о host сохраняются в `.local/preflight.json`. Успешный preflight не доказывает запуск приложения. `up` собирает образы и ждёт readiness API/SQL/worker. Если host не подходит или заняты порты, он должен остановиться с ошибкой; не открывать внешний bind как обход.

На том же хосте интерфейс доступен по `http://127.0.0.1:8787`. Для удалённого собственного ARM-хоста использовать SSH-туннель с локального компьютера:

```sh
ssh -N -L 127.0.0.1:8787:127.0.0.1:8787 -L 127.0.0.1:9080:127.0.0.1:9080 user@your-arm-host
```

Имя хоста и пользователя здесь placeholders. Порты должны быть свободны локально; SQL не туннелируется. В браузере открыть ровно `http://127.0.0.1:8787`, поскольку Origin/CSRF проверяются точно. Никаких публичных dev-аккаунтов.

## Smoke и нагрузка

```sh
node infra/arm/probe.mjs --players 2 --seconds 15 --out infra/arm/results/smoke.json
node infra/arm/probe.mjs --players 10 --seconds 300 --out infra/arm/results/ten-cars.json
```

Probe создаёт настоящие гостевые сессии через API, получает подписанные билеты, открывает WebSocket и подаёт ограниченный 60 Hz input, направляющий машины по овалу. Он не знает ticket secret и не подделывает результат гонки. После финиша начинает новую тренировочную попытку. На время прогона не входить в тот же worker вручную: максимум 10 мест, отключённые места резервируются на 30 секунд. Между независимыми прогонами подождать освобождения мест.

Сам генератор дополнительно проверен на macOS dev-стенде с `--expect local --players 10 --seconds 15`: все 10 клиентов подключились, получили snapshots и двигались, ошибок нет. Это проверка инструмента и локального протокола, не Docker/ARM performance result.

В отдельном терминале этого же ARM-хоста:

```sh
node infra/arm/monitor.mjs --seconds 320 --out infra/arm/results/resources.ndjson
```

Monitor записывает container CPU%, memory working-set display, RSS основного процесса из `/proc`, OOM/health и I/O. RSS PostgreSQL parent не включает дочерние backend-процессы; container memory и main-process RSS нельзя складывать как разные расходы. Недоступный RSS остаётся `null`, а не нулём. Docker CPU 100% означает примерно одно загруженное логическое ядро; несколько ядер могут дать больше 100%. [Docker stats](https://docs.docker.com/reference/cli/docker/container/stats/)

Probe пишет p50/p95/p99 времени прихода snapshots, ping RTT и input-ack RTT, наблюдаемую частоту server ticks и p99 event-loop delay генератора нагрузки. **Ни один из этих показателей не является длительностью вычисления физики.** `physicsComputationDurationMs` намеренно `null`: до закрытия 2.7 нужно инструментировать CPU-время физического тика, стоимость snapshots и паузы отдельно.

## План замеров

1. Зафиксировать commit, dirty state, image-lock, artifact hashes, CPU model, 4/8 выделенных либо shared cores, RAM, kernel, governor и фоновые процессы. Секреты не включать.
2. Проверить health, пару реальных браузеров через SSH, input/focus, reconnect, финиш и отсутствие GDScript ошибок. Отдельно проверить серверный процесс действительно ARM64.
3. Прогреть и измерить 1/2/5/10 машин, не менее трёх повторов с одинаковыми сценариями. Нынешний worker не содержит car collisions, предметов, ботов и production-контента, что ограничивает переносимость результата.
4. Записать CPU/RSS/working set, OOM, реальную p99 стоимость физического тика, число пропущенных бюджетов 16.67 мс, snapshot encode time, сетевой трафик, RTT/ack и stalls. Проверить, что сам load generator не является bottleneck.
5. Сравнить реальные 4- и 8-ядерные хосты. Текущие limits: SQL 1 CPU/1 GiB, API 1 CPU/512 MiB, worker 2 CPU/1 GiB. `RACE_CPUS` в приватном env можно изменить для контролируемого эксперимента; CPU quota не превращает 8 физических ядер в идентичный 4-ядерный CPU.
6. Только после этого добавлять несколько workers, allocator и сценарий заполненных лобби. Сейчас один worker на фиксированном порту; `--scale race` не поддержан. Не умножать результат одного процесса на число ядер как готовую вместимость.

Прогон через SSH показывает функцию браузера, но добавляет tunnel overhead. WSS/WebRTC/TURN, мобильный Web, WAN latency/loss и стоимость проверяемых campaign-сессий остаются отдельными экспериментами.

## Остановка и проверки

```sh
node infra/arm/stand.mjs logs
node infra/arm/stand.mjs down
node --test infra/arm/probe.test.mjs infra/arm/docker-endpoint.test.mjs
```

`down` останавливает только этот Compose project и сохраняет SQL volume. Автоматического удаления данных, аренды, apt-install или изменения firewall нет. Повторный `init` не меняет ключи и не переключает image versions молча.

Проверено здесь: JavaScript/TypeScript syntax, YAML parsing и отсутствие published ports, 3 unit-теста функций probe и 5 тестов Docker endpoint guard, отказ launcher/monitor на macOS. Linux ARM Docker build/run, разрешение image digests, полная загрузка стенда и нагрузочные результаты **не проверены**. PostgreSQL 18.6 выбран как текущий security-fix release ветки 18, отдельно от portable PostgreSQL 18.4 в существующем macOS dev-launcher. [PostgreSQL 18.6](https://www.postgresql.org/docs/release/18.6/), [Node.js 24.21.0](https://nodejs.org/en/blog/release/v24.21.0)
