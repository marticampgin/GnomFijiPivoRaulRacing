# Godot: технический прототип

Godot **4.7.2 stable**, GDScript, Compatibility / WebGL 2.0, single-thread Web.
Одна машина, три круга и цикл дрифта с ускорением. Текущие исходники используют
авторский маршрут длиной 798 м с перепадом около 16 м; старый овал
сохранён как отдельная regression fixture и в прежнем локальном стенде.
В исходниках подключены внутренний environment study и Blender/GLB blockout:
гном в красном колпаке, бирюзовый карт, каменная дорога, лес, мост, замок и водопады.
Это проверка композиции и производства ассетов, не принятые финальные модели,
UV/rig/LOD или окончательное направление окружения. Состав реально обновлённого
браузерного стенда и его проверки фиксируются в [delivery](../docs/delivery.md).
Источники и ограничения: [art/README](art/README.md).

## Запуск

Полный браузерный путь с аккаунтом и headless-сервером описан в [README](../README.md#локальный-запуск).
Web-экспорту нужна HTML-оболочка и API: простой статический сервер не заменяет этот путь.

Для самостоятельной проверки физики открыть `project.godot` в Godot 4.7.2 и запустить главную сцену.
Native-preview создаёт локальную машину без авторизации, рейтинга и наград.

```sh
godot --headless --path game --editor --import
godot --headless --path game --script res://tests/vehicle_probe.gd
godot --headless --path game --script res://tests/track_probe.gd
godot --headless --path game --script res://tests/authored_track_probe.gd
godot --headless --path game --fixed-fps 60 --script res://tests/authored_drive_probe.gd
godot --headless --path game --script res://tests/route_study_probe.gd
godot --headless --path game --script res://tests/camera_probe.gd
godot --headless --path game --script res://tests/authored_kart_probe.gd
godot --headless --path game --script res://tests/graphics_settings_probe.gd
godot --headless --path game --script res://tests/visual_asset_probe.gd
godot --headless --path game --script res://tests/network_protocol_probe.gd
godot --headless --path game --script res://tests/network_client_probe.gd
godot --headless --path game --script res://tests/network_resume_probe.gd
```

Зафиксированные templates, контрольные суммы и Web/ARM64 export: [toolchain](../docs/toolchain.md).
Серверные билеты, лимиты и запуск интеграционного теста: [сетевой прототип](../docs/network-prototype.md).
Выбор контроллера, дрифт и локальная гравитация: [vehicle controller](../docs/vehicle-controller.md).
Формат маршрута, bake, checkpoints и границы проверки: [authored route](track/AUTHORED_ROUTE.md).
Редактируемый герой, GLB и ограничения blockout: [art source](../art-source/hero/README.md).

## Визуальный этап

`authored_track_study.gd` строит визуальную сцену поверх того же bake, не добавляя
физические тела. Study проверен 18 assertions: совпадение дороги с коллизиями,
наличие материала/ориентиров, переключение качества и неизменность simulation hash.
Четыре native-ракурса проверяют композицию, но не заменяют браузерную приёмку.

Камера вынесена в `view/race_camera.gd`: chase/look-back, реакция на уклон,
сброс после teleport/recovery и защита камеры/near plane от дороги и барьеров.
Probe прошёл 376 проверок математики, столкновений и framing, не принятия арта.
Поступательное движение отслеживается без накопления отставания на скорости;
сглаживание применяется к относительному положению и направлению взгляда.

В Web-меню реализованы Standard/Low и reduced-effects. Low уменьшает render scale,
дальность теней и плотность/дальность листвы; reduced-effects приглушает водную
анимацию и эффекты ускорения. Коллизии, checkpoints и физические параметры не
меняются. Это не готовые LOD ассетов и не подтверждение бюджета десяти машин.

## Управление

`input/driver_input.gd` читает логические действия один раз за physics tick.
Будущий touch adapter должен передавать те же действия, не менять физику напрямую.

| Действие | Клавиатура | Геймпад |
| --- | --- | --- |
| Поворот | A/D, стрелки | Левый стик |
| Газ | W, вверх | Правый триггер |
| Тормоз | S, вниз | Левый триггер |
| Дрифт | Пробел | A / нижняя кнопка |
| Вид назад | C | Пока не назначено |
| Меню Web | Escape | Пока не подключено |

Предметы Q/E и соответствующие действия геймпада зарезервированы,
но ещё не реализованы. В меню браузерного заезда доступны возврат на трассу и выход.
Открытое меню и потеря фокуса снимают ввод; онлайн-гонка при этом не останавливается.

## Границы

- Headless worker авторитетно считает физику на 60 Hz и отправляет снимки на 20 Hz.
- Web-клиент предсказывает свою машину, сверяется с сервером и интерполирует соперников.
- До 10 подключений ограничены протоколом; это не измеренная production-ёмкость сервера.
- Машины пока не сталкиваются друг с другом; есть столкновения с трассой.
- Нет предметов, ботов, разрушаемости, рейтинга, наград и постоянных результатов гонки.
- Отработаны прыжок и отдельная локальная гравитация, но непрерывная трасса с 360-градусными участками ещё впереди.
- Локальный WS допустим только для разработки. Сравнение WSS и WebRTC/native extension/TURN остаётся открытым.
- ARM64 cross-export проверяет сборку, не запуск на Linux ARM и не FPS/CCU.
- Мобильная компоновка оболочки не означает готовое сенсорное управление или поддержанную мобильную игру.

Источники: [Web export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html),
[Godot](https://godotengine.org/). Секреты API и worker никогда не включаются в Web export.
