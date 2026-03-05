# osu! Linux Installer (Stable)

**Версия:** v4.2.0
**Лицензия:** MIT
**Языки:** [English](README.md) | [Русский](README_RU.md)

Модульный Bash-инсталлятор для автоматизированного развёртывания и настройки клиента osu! (stable) в среде Linux. Приоритет — минимальная задержка, корректная интеграция с системой и поддержка современных графических стеков.

Использует `yad` (Yet Another Dialog) для графического интерфейса конфигурации. Также поддерживается полностью автономный CLI-режим.

## Основные возможности

- **Мультиплатформенность:** Arch Linux, Debian/Ubuntu, Fedora, Void Linux. NixOS частично.
- **Графика:** OpenGL или DXVK (трансляция DirectX → Vulkan для снижения задержки ввода).
- **Оконная система:** X11 (стабильный) или нативный Wayland-драйвер (экспериментальный, Wine 11.3+).
- **Шрифты:** Установка CJK-шрифтов и патчинг реестра Wine — WenQuanYi, Noto Sans CJK, Koruri или системные шрифты.
- **Аудио:** PulseAudio/PipeWire или ALSA, с настроенными переменными задержки.
- **Синхронизация:** FSync / ESync / NTSync (NTSync требует Linux 6.8+ и `/dev/ntsync`).
- **GameMode:** Опциональная интеграция с [Feral GameMode](https://github.com/FeralInteractive/gamemode).
- **Интеграция с системой:** Desktop-запись, регистрация MIME-типов для `.osz` / `.osk` / `.osr`, скрипт-обёртка.
- **Удобные симлинки:** `~/osu/{Songs,Skins,Logs,Chat}` ведут прямо в Wine-префикс.
- **Команды обслуживания:** обновление, удаление, проверка состояния, экспорт/импорт конфига, отладочный запуск.

## Системные требования

- **ОС:** Linux (Arch, Debian, Fedora, Void или производные).
- **Зависимости:** `curl`, `unzip`, `winetricks`, `yad` — устанавливаются автоматически на поддерживаемых системах.
- **Wine:** Рекомендуется `wine-staging`. Стабильная ветка тоже поддерживается.

> **Пользователям NixOS:** Автоматическое разрешение зависимостей не поддерживается. Используйте [нативный форк](https://github.com/afanetd/linux-osu-stable-installer-nixos) от **afanetd**, либо установите `yad` и `wine` вручную и запустите с `--silent`.

## Установка

```bash
git clone https://github.com/Kitty-Hivens/linux-osu-stable-installer.git
cd linux-osu-stable-installer
chmod +x install.sh
./install.sh
```

> **Безопасность:** Права суперпользователя (через `pkexec`) запрашиваются **только** для установки системных пакетов. Сама игра устанавливается целиком в домашнюю директорию пользователя.

## Параметры Dashboard

При первом запуске открывается окно конфигурации:

| Параметр | Описание |
| :--- | :--- |
| **Install Location** | Директория Wine-префикса. По умолчанию: `~/.wine-osu` |
| **Wine Binary** | Автоопределение `wine-staging`. Можно указать кастомный путь (Proton, Wine-GE). |
| **Graphics API** | **OpenGL** — стандартный рендер, подходит для старого железа. **DXVK** — трансляция в Vulkan, рекомендуется для современных GPU. |
| **Window Driver** | **X11** — стабильный, совместим со всеми композиторами. **Wayland** — нативный драйвер Wine, убирает оверхед XWayland. *Экспериментальный.* |
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
  -d, --driver DRIVER    Драйвер окна: 'x11' или 'wayland'
  -f, --font FONT        Шрифт: 'wqy', 'noto', 'koruri', 'system', 'skip'
      --rpc true/false   Discord RPC Bridge (по умолчанию: true)
      --dotnet TYPE      Рантайм: 'net48' или 'mono'
      --audio TYPE       Аудио: 'pulse' или 'alsa'
      --no-sync          Отключить FSync/ESync/NTSync
      --no-gamemode      Отключить GameMode
      --links-dir DIR    Директория симлинков (по умолчанию: ~/osu)
  -s, --silent           Автономный режим без GUI

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
| **Стабильность** | ✅ Рекомендуется | ⚠️ Экспериментальный |
| **FSync/ESync/NTSync** | ✅ Можно включать | ❌ Обязательно отключить — вызывает краш |
| **Время установки** | ~5–10 мин | Мгновенно (встроен в Wine) |
| **Симптом краша** | — | Ассерт `mono-error.c:647` при старте |

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

### Настройка параметров

Все переменные запуска хранятся в `~/.config/osu-importer/osu-env.conf`. Файл можно редактировать напрямую:

```bash
# Отключить VSync в OpenGL:
export vblank_mode=0

# Уменьшить аудио-буфер для меньшей задержки (может вызывать треск на слабых системах):
export STAGING_AUDIO_DURATION=5000
export PULSE_LATENCY_MSEC=30
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

- **Конфайнмент курсора на Wayland:** На Hyprland и Sway курсор может некорректно ограничиваться областью окна. Используйте X11-драйвер.
- **Wine Mono + FSync:** Включение любого примитива синхронизации (FSync/ESync/NTSync) совместно с Wine Mono вызывает краш при старте (`mono-error.c:647`). Используйте MS .NET 4.8 или отключите синхронизацию.
- **NixOS:** Автоматическая установка зависимостей невозможна. Установите `yad` через `configuration.nix` или `nix-env`, затем запустите с `--silent`.

## Лицензия

Распространяется под лицензией MIT. Подробности — в файле [LICENSE](LICENSE).
