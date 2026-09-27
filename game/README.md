# Godot: технический прототип

Godot **4.7.2 stable**, GDScript, Compatibility / WebGL 2.0, single-thread Web.
Одна трасса, четыре стиля, 1–4 локальных игрока с ботами до десяти участников,
девять предметов и ручной CTR-цикл дрифта. Текущие исходники используют
авторский маршрут длиной 825,45 м с перепадом около 16 м; старый овал
сохранён как отдельная regression fixture и в прежнем локальном стенде.
В исходниках подключены внутренний environment study и Blender/GLB blockout:
гном в красном колпаке, бирюзовый карт, каменная дорога, лес, мост, замок и водопады.
Это проверка композиции и производства ассетов, не принятые финальные модели,
UV/rig/LOD или окончательное направление окружения. Состав реально обновлённого
браузерного стенда и его проверки фиксируются в [delivery](../docs/delivery.md).
Источники и ограничения: [art/README](art/README.md).

## Запуск

Локальный режим и отдельный сетевой полигон описаны в [README](../README.md#локальный-запуск).
Локальная гонка после загрузки ресурсов не требует API/аккаунта; для неё служит
`node scripts/local-web.mjs --detach`. Сетевой полигон требует backend и worker.

Для самостоятельной проверки физики открыть `project.godot` в Godot 4.7.2 и запустить главную сцену.
Native-preview создаёт локальную машину без авторизации, рейтинга и наград.

```sh
godot --headless --path game --editor --import
godot --headless --path game --script res://tests/vehicle_probe.gd
godot --headless --path game --script res://tests/track_probe.gd
godot --headless --path game --script res://tests/authored_track_probe.gd
godot --headless --path game --fixed-fps 60 --script res://tests/authored_drive_probe.gd
godot --headless --path game --fixed-fps 60 --script res://tests/slope_drive_probe.gd
godot --headless --path game --script res://tests/route_study_probe.gd
godot --headless --path game --script res://tests/camera_probe.gd
godot --headless --path game --script res://tests/authored_kart_probe.gd
godot --headless --path game --script res://tests/graphics_settings_probe.gd
godot --headless --path game --script res://tests/visual_asset_probe.gd
godot --headless --path game --script res://tests/network_protocol_probe.gd
godot --headless --path game --script res://tests/network_client_probe.gd
godot --headless --path game --script res://tests/network_resume_probe.gd
node scripts/test-input.mjs
```

Зафиксированные templates, контрольные суммы и Web/ARM64 export: [toolchain](../docs/toolchain.md).
Серверные билеты, лимиты и запуск интеграционного теста: [сетевой прототип](../docs/network-prototype.md).
Выбор контроллера, дрифт и локальная гравитация: [vehicle controller](../docs/vehicle-controller.md).
Формат маршрута, bake, checkpoints и границы проверки: [authored route](track/AUTHORED_ROUTE.md).
Редактируемый герой, GLB и ограничения blockout: [art source](../art-source/hero/README.md).

## Визуальный этап

`authored_track_study.gd` строит визуальную сцену поверх того же bake. Непрозрачные
скалы, архитектура и стволы получают одну client-only camera collision mesh:
layer 4, mask 0. Машины используют mask 1; сервер этот набор не создаёт.
Study проверен 58 assertions: совпадение дороги с коллизиями, направление всех
36 шевронов, ориентиры, качество и неизменность simulation hash.
Четыре native-ракурса проверяют композицию, но не заменяют браузерную приёмку.

Камера вынесена в `view/race_camera.gd`: chase/look-back, реакция на уклон,
сброс после teleport/recovery и защита камеры/near plane от дороги, барьеров
и непрозрачного окружения. Вода, листва и другие машины не сокращают boom.
Пять лучей проверяют центр и углы near plane; это не непрерывный sphere sweep
и не окончательная приёмка камеры по всей ширине трассы.
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
| Газ | Space | A |
| Тормоз / назад после остановки | C | B |
| Начало / удержание дрифта | Shift либо E | LB либо RB |
| Турбо в окне шкалы | Противоположная кнопка Shift/E | Противоположное плечо LB/RB |
| Следующий предмет | Q | Y |
| Вид назад | F | X |
| Меню Web | Tab / Escape | Menu |

До трёх ручных турбо за один дрифт. Отпускание не даёт ускорения; раннее нажатие
или пропущенное окно требуют нового дрифта. Короткое выпрямление руля сохраняет
удерживаемый дрифт, но заряд растёт только при реальном скольжении. Предметы
хранятся в FIFO-очереди из двух: одно свежее Q/Y применяет старший, удержание
не повторяется; меньший предмет HUD является резервом, а не отдельной кнопкой.

Альтернативные профили сохраняют педали WASD/стрелки или RT/LT. Задний вид:
C для неаркадной клавиатуры, X для standard и B для alternate. Все профили
используют общие новые LB/RB (Shift/E) и Y (Q), без прежнего выбора слотов.
Новый P1 автоматически получает доступный геймпад после обнаружения браузером,
если устройство не выбрано явно. Меню использует стик/крестовину, A подтверждение,
B назад. В браузере может понадобиться первое нажатие на подключённом геймпаде.
Открытое меню и потеря фокуса снимают ввод; локальная гонка останавливается
целиком, онлайн-гонка продолжает серверную симуляцию. После паузы/переподключения
удержанные действия должны быть отпущены. Синтетические тесты не заменяют
проверку физического Xbox по Bluetooth.

## Границы

- Headless worker авторитетно считает физику на 60 Hz и отправляет снимки на 20 Hz.
- Web-клиент предсказывает свою машину, сверяется с сервером и интерполирует соперников.
- До 10 подключений ограничены протоколом; это не измеренная production-ёмкость сервера.
- Машины сталкиваются друг с другом и окружением; импульс зависит от угла и относительной скорости. Контакт не уничтожает карт, разрушение предметом и вылет допускают возврат.
- Есть боты, предметы и прочность; рейтинга, наград и постоянных результатов гонки пока нет.
- Текущая совместимость: wire 9, vehicle state 2, loadout `prototype-v13`, vehicle balance `vehicle-prototype-v13`; старые клиенты отклоняются.
- Отработаны прыжок и отдельная локальная гравитация, но непрерывная трасса с 360-градусными участками ещё впереди.
- Локальный WS допустим только для разработки. Сравнение WSS и WebRTC/native extension/TURN остаётся открытым.
- ARM64 cross-export проверяет сборку, не запуск на Linux ARM и не FPS/CCU.
- Мобильная компоновка оболочки не означает готовое сенсорное управление или поддержанную мобильную игру.

Источники: [Web export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html),
[Godot](https://godotengine.org/). Секреты API и worker никогда не включаются в Web export.
