# osu! Linux Installer (Stable)

**Версия:** v5.0.0
**Лицензия:** MIT
**Языки:** [English](README.md) | [Русский](README_RU.md)

Модульный Bash-инсталлятор для автоматизированного развёртывания и настройки клиента osu! (stable) в среде Linux. Приоритет — минимальная задержка, корректная интеграция с системой и поддержка современных графических стеков.

Использует `gum` для опрятного TUI-интерфейса конфигурации в терминале. Также поддерживается полностью автономный CLI-режим.

## Основные возможности

- **Мультиплатформенность:** Arch Linux, Debian/Ubuntu, Fedora, Void Linux и NixOS (first-class через встроенный Nix flake).
- **Графика:** OpenGL или DXVK (трансляция DirectX → Vulkan для снижения задержки ввода).
- **Оконная система:** Нативный Wayland (по умолчанию, без оверхеда XWayland) или X11 (фолбэк). Драйвер переключается через реестр Wine — `WINEWAYLAND=1` сам по себе ничего не делает.
- **Шрифты:** Установка CJK-шрифтов (Noto Sans CJK, WenQuanYi, Koruri или системные) плюс фолбэк по глифам, чтобы декоративные dingbats в тайтлах карт рисовались, а не превращались в квадраты.
- **Аудио:** PulseAudio/PipeWire или ALSA, с настроенными переменными задержки.
- **Синхронизация:** FSync / ESync / NTSync (NTSync требует Linux 6.8+ и `/dev/ntsync`).
- **GameMode:** Опциональная интеграция с [Feral GameMode](https://github.com/FeralInteractive/gamemode).
- **Интеграция с системой:** Desktop-запись, регистрация MIME-типов для `.osz` / `.osk` / `.osr`, скрипт-обёртка.
- **Удобные симлинки:** `~/osu/{Songs,Skins,Logs,Chat}` ведут прямо в Wine-префикс.
- **Импортёр карт:** двойной клик по `.osz` / `.osk` / `.osr` импортирует в запущенную игру; несколько файлов сразу — батчем за один проход.
- **Команды обслуживания:** обновление, удаление, проверка состояния, экспорт/импорт конфига, отладочный запуск.

## Системные требования

- **ОС:** Linux (Arch, Debian, Fedora, Void или производные).
- **Зависимости:** `curl`, `unzip`, `winetricks`, `gum` — устанавливаются автоматически на поддерживаемых системах.
- **Wine:** Рекомендуется `wine-staging` (он же по умолчанию). Стабильная ветка тоже поддерживается.

> **Пользователям NixOS:** First-class через встроенный Nix flake — Nix сам предоставляет все зависимости, ручная настройка не нужна. См. [NixOS](#nixos).

## Установка

```bash
git clone https://github.com/Kitty-Hivens/linux-osu-stable-installer.git
cd linux-osu-stable-installer
chmod +x install.sh
./install.sh
```

> **Безопасность:** Права суперпользователя (через `pkexec`) запрашиваются **только** для установки системных пакетов. Сама игра устанавливается целиком в домашнюю директорию пользователя.

### NixOS

В репозитории есть Nix flake, поэтому Nix предоставляет все зависимости (Wine staging, `gum`, `winetricks`, шрифты, `ydotool`, ...) — без установки системных пакетов и без обходного `--silent`:

```bash
# установка / настройка в один заход
nix run github:Kitty-Hivens/linux-osu-stable-installer

# или dev-shell со всем на PATH, и запускаешь сам
nix develop github:Kitty-Hivens/linux-osu-stable-installer
./install.sh
```

## Параметры Dashboard

При первом запуске открывается интерактивный TUI-дашборд в терминале (на `gum`):

| Параметр | Описание |
| :--- | :--- |
| **Install Location** | Директория Wine-префикса. По умолчанию: `~/.wine-osu` |
| **Wine Binary** | Автоопределение `wine-staging`. Можно указать кастомный путь (Proton, Wine-GE). |
| **Graphics API** | **OpenGL** — стандартный рендер, подходит для старого железа. **DXVK** — трансляция в Vulkan, рекомендуется для современных GPU. |
| **Window Driver** | **Wayland** (по умолчанию) — нативный драйвер Wine, без оверхеда XWayland. **X11** — фолбэк для максимальной совместимости с композиторами. |
| **Fonts** | Замена системного шрифта Windows для корректного отображения CJK-символов. |
| **Discord RPC** | Установка [rpc-bridge](https://github.com/EnderIce2/rpc-bridge) для Rich Presence в Linux-клиенте Discord. |
| **.NET Runtime** | **MS .NET 4.8** (рекомендуется) или **Wine Mono** (экспериментальный). См. примечание ниже. |
| **Audio Backend** | **PulseAudio/PipeWire** (по умолчанию) или **ALSA** для минимальной задержки. |
| **FSync/ESync** | Примитивы синхронизации для снижения нагрузки на CPU. |
| **GameMode** | Включает обёртку `gamemoderun`, если установлен [GameMode](https://github.com/FeralInteractive/gamemode). |
| **Symlinks Directory** | Где создать ярлыки Songs/Skins/Logs/Chat. По умолчанию: `~/osu` |

## CLI

```
./install.sh [OPTIONS]

Установка:
  -p, --prefix DIR       Директория Wine-префикса (по умолчанию: ~/.wine-osu)
  -w, --wine BIN         Бинарник Wine или путь
  -a, --api API          Графический API: 'opengl' или 'dxvk'
  -d, --driver DRIVER    Драйвер окна: 'x11' или 'wayland' (по умолчанию: wayland)
  -f, --font FONT        Шрифт: 'wqy', 'noto', 'koruri', 'system', 'skip'
      --rpc true/false   Discord RPC Bridge (по умолчанию: true)
      --dotnet TYPE      Рантайм: 'net48' или 'mono'
      --audio TYPE       Аудио: 'pulse' или 'alsa'
      --no-sync          Отключить FSync/ESync/NTSync
      --no-gamemode      Отключить GameMode
      --links-dir DIR    Директория симлинков (по умолчанию: ~/osu)
  -s, --silent           Автономный режим без TUI

Обслуживание:
      --update           Переприменить настройки к существующей установке
      --uninstall        Удалить osu! и все файлы интеграции
      --health-check     Проверить целостность установки
      --export-config    Экспортировать конфиг в osu-config-backup.tar.gz
      --import-config F  Импортировать конфиг из файла резервной копии
      --launch           Запустить osu! с полным выводом Wine (режим отладки)
```

## Выбор рантайма: .NET 4.8 или Wine Mono

Это наиболее важный параметр конфигурации:

| | MS .NET 4.8 | Wine Mono |
| :--- | :--- | :--- |
| **Стабильность** | Рекомендуется | Экспериментальный |
| **FSync/ESync/NTSync** | Можно включать | Обязательно отключить (вызывает краш) |
| **Время установки** | ~5-10 мин | Мгновенно (встроен в Wine) |
| **Симптом краша** | нет | Ассерт `mono-error.c:647` при старте |

Если вы выбрали Mono и osu! падает при запуске — либо переключитесь на .NET 4.8 через `--update`, либо отключите синхронизацию в `~/.config/osu-importer/osu-env.conf`.

## После установки

### Удобные симлинки

После установки данные osu! доступны напрямую:

```
~/osu/
├── Songs  →  ~/.wine-osu/.../osu!/Songs
├── Skins  →  ~/.wine-osu/.../osu!/Skins
├── Logs   →  ~/.wine-osu/.../osu!/Logs
└── Chat   →  ~/.wine-osu/.../osu!/Chat
```

Если любая из этих директорий уже существовала как реальная папка — инсталлятор создаёт резервную копию (`Songs.bak.TIMESTAMP`), переносит содержимое в Wine-префикс и создаёт симлинк.

### Импорт карт

Двойной клик по `.osz`, `.osk` или `.osr` в файловом менеджере импортирует их в запущенную osu! (игра запускается сама, если ещё не открыта). Выбор нескольких `.osz` разом импортирует их батчем за один проход, а не по попапу на файл. Уведомления по умолчанию тихие — поставь `OSU_IMPORTER_DEBUG=1` в конфиге для пофайловых деталей.

### Настройка параметров

Все переменные запуска хранятся в `~/.config/osu-importer/osu-env.conf`. Файл можно редактировать напрямую:

```bash
# Отключить VSync в OpenGL:
export vblank_mode=0

# Уменьшить аудио-буфер для меньшей задержки (может вызывать треск на слабых системах):
export STAGING_AUDIO_DURATION=5000
export PULSE_LATENCY_MSEC=30

# Подробные уведомления импорта (пофайлово / запуск / рескан):
export OSU_IMPORTER_DEBUG=1
```

### Отладочный запуск

Для диагностики проблем запустите osu! напрямую из терминала:

```bash
./install.sh --launch
```

## Удаление

```bash
./install.sh --uninstall
```

Или вручную:

```bash
rm -rf ~/.wine-osu
rm -f ~/.local/share/applications/osu-stable.desktop
rm -f ~/.local/share/applications/osu-importer.desktop
rm -f ~/.local/share/mime/packages/osu-file-types.xml
rm -rf ~/.config/osu-importer
# Симлинки:
rm -f ~/osu/Songs ~/osu/Skins ~/osu/Logs ~/osu/Chat
```

## Известные проблемы

- **Raw input на Wayland:** нативный Wayland-драйвер не даёт настоящий raw input — выключи Raw Input в osu! и задавай чувствительность через DPI мыши, и играй в **Borderless**, а не exclusive fullscreen (он мерцает на смене фокуса). Нужен hardware-raw — используй X11-драйвер.
- **Wine Mono + FSync:** Включение любого примитива синхронизации (FSync/ESync/NTSync) совместно с Wine Mono вызывает краш при старте (`mono-error.c:647`). Используйте MS .NET 4.8 или отключите синхронизацию.
- **NixOS:** Запускайте через встроенный flake (`nix run` / `nix develop`), чтобы Nix предоставил зависимости — см. [NixOS](#nixos).

## Лицензия

Распространяется под лицензией MIT. Подробности — в файле [LICENSE](LICENSE).
