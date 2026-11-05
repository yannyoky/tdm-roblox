# TDM: Банда против силовиков

Командный шутер для Roblox со сценариями. Две стороны: **Банда** и **Силовики**.

Режимы в MVP:

- **Перестрелка** — классический командный бой до 50 убийств или 8 минут, возрождение через 3 секунды.
- **Капт** — одна команда атакует район, другая держит. Раунды без возрождения, стороны меняются, матч до 3 побед.

Между матчами игроки голосуют в лобби за следующий режим.

## Как запустить

1. Установите [Roblox Studio](https://create.roblox.com/) и [VS Code](https://code.visualstudio.com/).
2. Установите [Rokit](https://github.com/rojo-rbx/rokit) и в папке проекта выполните `rokit install` (поставит Rojo).
3. В Studio установите плагин Rojo (Plugins → Manage Plugins или из [Creator Store](https://create.roblox.com/store/asset/13916111004)).
4. В папке проекта выполните `rojo serve`.
5. В Studio откройте новое место (Baseplate), во вкладке Plugins нажмите **Rojo → Connect**. Код появится в игре.
6. Для сохранений: Game Settings → Security → **Enable Studio Access to API Services** (место нужно один раз опубликовать).
7. Тест на двух игроках: вкладка **Test → Clients and Servers**, 2 игрока. Одному тоже можно: в Studio матч стартует с 1 игроком.

Если в Workspace нет папки `Map`, игра сама построит тестовую арену. Свою карту стройте в Studio по структуре:

```
Workspace/Map/
  Spawns/Bandits/  -- детали, где появляется Банда
  Spawns/Gov/      -- детали, где появляются Силовики
  Spawns/Lobby/    -- детали в лобби
  CapturePoints/   -- плоские прозрачные детали-зоны для капта (CanCollide и CanQuery выключены)
```

Сохраните карту в файл места (`.rbxl`), сам файл в Git не попадает.

## Как устроен код

```
src/
  shared/              -- ReplicatedStorage.Shared, видно и серверу, и клиенту
    Config/            -- все настройки: оружие, режимы, команды, награды, магазин
    Net.luau           -- сетевые события
  server/              -- ServerScriptService.Server
    Services/
      MatchService     -- лобби, голосование, команды, появление, матч, итоги
      WeaponService    -- серверная проверка выстрелов и урона
      DataService      -- уровень, опыт, монеты, сохранение
      ShopService      -- Game Passes и Developer Products
      MapService       -- карта или тестовая арена
    Modes/
      ModeBase         -- общий интерфейс режима
      TDM, Capture     -- режимы
  client/              -- StarterPlayerScripts.Client
    WeaponController   -- стрельба, перезарядка, трассеры
    Hud                -- интерфейс
```

Попадания считает сервер: клиент сообщает только «выстрелил отсюда туда», сервер проверяет скорострельность, патроны и стены.

### Как добавить новый сценарий

1. Скопируйте `src/server/Modes/TDM.luau` в новый файл, например `Drop.luau`.
2. Переопределите нужные функции (`Start`, `OnTick`, `OnPlayerKilled`, `CanRespawn`, `GetWinner`, `Cleanup`). Описание — в `ModeBase.luau`.
3. Добавьте запись в `src/shared/Config/Modes.luau` (в `List` и `Order`). Режим сразу появится в голосовании.

## Монетизация

1. Опубликуйте игру, затем в [Creator Hub](https://create.roblox.com/dashboard/creations) создайте Game Pass «VIP» и Developer Products (пакеты монет, буст опыта), задайте цены.
2. Вставьте их Id в `src/shared/Config/Shop.luau`. Пока Id равен 0, кнопка в магазине показывает «скоро».

Платная только косметика и удобство: VIP даёт +25% опыта и монет, буст даёт x2 опыта на час. Оружие открывается игрой.

## Что дальше

- Выбор оружия и разблокировка по уровню, скины за монеты.
- Сценарии: Дроп, Командир, Охота за головами, Ограбление, Перехват поставки.
- Банды и ганг-зоны на общей карте города.
- Переход сохранений на ProfileStore перед большим запуском.
