# OpenWrt для Xiaomi BE3600 (RD16)

Сборка OpenWrt (ветка main, ядро Linux 6.18) для роутера **Xiaomi BE3600, модификация RD16**
с открытыми драйверами: ath12k для Wi‑Fi 7 и DSA для коммутатора.
Проект — это набор патчей и скрипт сборки поверх
[fivefold3/openwrt-gl-be3600](https://github.com/fivefold3/openwrt-gl-be3600) (GL.iNet BE3600 на том же SoC).

OpenWrt ставится в **системный слот A**. В слоте B остаётся заводская прошивка Xiaomi:
к ней можно вернуться одной командой в U-Boot. Заводской U-Boot переключается на неё и сам,
если OpenWrt несколько раз подряд не загрузилась.

> Проект неофициальный и экспериментальный. Всё, что вы делаете с роутером, — на ваш риск.
> Перед установкой сохраните раздел ART, где лежит калибровка Wi‑Fi (см. «Установка»).

## Оборудование

| | |
|---|---|
| SoC | Qualcomm IPQ5332, 4× Cortex‑A53 |
| ОЗУ | 256 МБ (Linux доступно ~170 МБ, остальное занимают Q6 Wi‑Fi и TrustZone) |
| Флеш | 128 МБ SPI‑NAND Winbond W25N01KW |
| Ethernet | Motorcomm YT9215S: 1× WAN + 3× LAN, 1 Гбит/с (2,5G‑порта у RD16 нет) |
| Wi‑Fi 2,4 ГГц | IPQ5332 (встроенный), 2×2 |
| Wi‑Fi 5 ГГц | QCN6432, 2×2 |
| Консоль | UART 115200 8N1 |

## Что работает

| Функция | Состояние |
|---|---|
| Загрузка из слота A, UBI + squashfs, overlay на UBIFS | ✅ |
| Возврат на заводскую прошивку (слот B) | ✅ вручную и автоматически после неудачных загрузок |
| Коммутатор: WAN/LAN, MAC‑адреса из окружения U-Boot | ✅ |
| Wi‑Fi 2,4 ГГц | ✅ HE20 |
| Wi‑Fi 5 ГГц | ✅ HE80, ~600 Мбит/с TCP на один клиент 2×2 |
| sysupgrade из LuCI или консоли (с сохранением настроек) | ✅ |
| Вариант с podkop + sing-box, WireGuard, zram‑swap | ✅ ~550 Мбит/с Wi‑Fi при работающем podkop |
| 160 МГц / DFS‑каналы | ❌ проверка на радары (CAC) не запускается надёжно |
| Wi‑Fi 7 (EHT) с регионом RU | ❌ запрещён таблицей регионов в прошивке Q6; с регионом US работает |
| Уровень сигнала и скорость приёма клиентов в LuCI | ⚠️ выключено ради CPU, включается параметром (см. ниже) |
| Кнопка reset | ⚠️ короткое нажатие — перезагрузка, ≥5 с — сброс настроек (стандарт OpenWrt); на железе не проверено |
| Кнопка mesh | ✅ включает/выключает оба радио Wi‑Fi |
| Светодиоды | ✅ как в стоке: синий — WAN поднят, оранжевый — WAN нет; мигают при загрузке, failsafe и обновлении |
| Аппаратное ускорение NSS/PPE (NAT, Wi‑Fi offload) | ❌ трафик обрабатывает CPU |

## Варианты прошивки

`build.sh` собирает два варианта из одного дерева:

| Вариант | Что внутри | Свободно ОЗУ* |
|---|---|---|
| `base` | OpenWrt + LuCI | ~23–28 МБ |
| `podkop` | base + [podkop](https://github.com/itdoginfo/podkop) 0.6.1, sing-box (без tailscale и gvisor), WireGuard, zram‑swap, русский LuCI | ~22 МБ при работающем podkop, плюс ~80 МБ zram |

\* `MemAvailable` при обоих работающих радио.

Для каждого варианта получаются такие файлы:
- `…-squashfs-factory.ubi` — первая установка в слот A (`ubiformat`);
- `…-squashfs-sysupgrade.bin` — обновление из работающей OpenWrt;
- `…-initramfs-uImage.itb` — только в `base`: загрузка в RAM по TFTP для установки и восстановления.
  Wi‑Fi в нём не запускается, чтобы образ `factory.ubi` гарантированно поместился в /tmp.

## Установка

OpenWrt всегда ставится в **слот A** (раздел `rootfs`), а заводская прошивка должна остаться
в **слоте B** (`rootfs_1`). Какой слот активен, показывает `flag_boot_rootfs` в окружении U-Boot:
`0` — A, `1` — B.

### Способ 1: с заводской прошивки по SSH, без UART

> Этот способ повторяет механизм обновления самой Xiaomi и скрипты
> [RomikB/xiaomi-be3600-overlay](https://github.com/RomikB/xiaomi-be3600-overlay).
> Автор этого проекта его не проверял, проверен только способ 2.

Нужен root‑доступ по SSH к заводской прошивке. Как его получить, здесь не описано:
overlay RomikB рассчитан на то, что доступ уже есть.

1. **Проверьте слот.** Заводская прошивка должна работать из слота B:
   ```
   nvram get flag_boot_rootfs        # должно быть 1
   ```
   Если выводит `0`, заводская прошивка сейчас в слоте A, и записывать OpenWrt нельзя:
   слот A затрёт работающую систему. Сначала обновите заводскую прошивку через веб‑интерфейс
   Xiaomi. Она запишется в другой слот и загрузится оттуда, после этого должно стать `1`.
2. **Сохраните ART** (калибровка Wi‑Fi) и перенесите файл на ПК:
   ```
   grep '"0:art"' /proc/mtd                         # номер раздела N
   dd if=/dev/mtdN of=/tmp/art.bin
   ```
3. **Скопируйте образ** `…-squashfs-factory.ubi` на роутер как `/tmp/root.ubi`
   (scp/sftp; в overlay RomikB есть `openssh-sftp-server`).
4. **Запишите слот A и переключитесь на него.**
   Со скриптами overlay RomikB (из `/data/scripts`):
   ```
   cd /tmp && sh /data/scripts/upgrade_other_rootfs.sh && sh /data/scripts/reboot_other_rootfs.sh
   ```
   Без них то же самое вручную:
   ```
   ubiformat /dev/mtd$(grep '"rootfs"' /proc/mtd | cut -d: -f1 | tr -dc 0-9) -f /tmp/root.ubi -s 2048 -O 2048 -y
   nvram set flag_boot_rootfs=0; nvram set flag_last_success=0; nvram set flag_try_sys1_failed=0
   nvram commit; reboot
   ```
5. Если OpenWrt не загрузится, U-Boot после нескольких неудачных попыток сам вернётся
   на заводскую прошивку в слоте B.

**С прошивки RomikB** (`openwrt-24-rd15`): его sysupgrade принимает UBI‑образ и пишет его
в **активный** слот. Если его OpenWrt работает из слота A (`nvram get flag_boot_rootfs` → `0`),
установите наш `…-squashfs-factory.ubi` через LuCI **без сохранения настроек**: конфиги
несовместимы (swconfig и qca‑wifi против DSA и mac80211). Если его прошивка в слоте B,
так делать нельзя: наша сборка рассчитана только на слот A.

### Способ 2: через UART и TFTP

Нужны UART, TFTP‑сервер на ПК (адрес 192.168.31.100) и кабель в любой LAN‑порт.
U-Boot роутера использует адрес 192.168.31.1.

1. **Загрузка в RAM.** В консоли U-Boot (прервите автозагрузку):
   ```
   setenv bootargs "console=ttyMSM0,115200n8 earlycon clk_ignore_unused"
   tftpboot 0x44000000 openwrt-qualcommbe-ipq53xx-xiaomi_rd16-initramfs-uImage.itb
   bootm 0x44000000
   ```
2. **Резервные копии** (из загруженной в RAM OpenWrt, по SSH на 192.168.1.1). Эти разделы
   прошивка никогда не пишет, но сохраните их до любых экспериментов:
   ```
   ssh root@192.168.1.1 'grep -E "art|rootfs" /proc/mtd'           # номера разделов
   ssh root@192.168.1.1 'nanddump -q /dev/mtdN' > art.bin             # N — строка "0:art"
   ssh root@192.168.1.1 'nanddump -q /dev/mtd20' > rootfs_1.bin       # "rootfs_1": заводская система (слот B)
   ```
   `rootfs_1.bin` понадобится ещё и для сборки (см. «Прошивка Wi‑Fi из заводского образа»).
3. **Запись слота A** (`mtd19`, раздел `rootfs`):
   ```
   cd /tmp && tftp -g -r openwrt-qualcommbe-ipq53xx-xiaomi_rd16-squashfs-factory.ubi 192.168.31.100
   ubiblock -r /dev/ubi0_1 2>/dev/null; ubidetach -p /dev/mtd19 2>/dev/null
   ubiformat /dev/mtd19 -f /tmp/openwrt-qualcommbe-ipq53xx-xiaomi_rd16-squashfs-factory.ubi -y
   reboot
   ```
   Если до этого был выбран слот B, в U-Boot выполните `setenv flag_boot_rootfs 0; saveenv`.
4. После загрузки поднимутся `Xiaomi-BE3600-2.4G` и `Xiaomi-BE3600-5G` с паролем **12345678**.
   Это тестовые значения: смените пароль Wi‑Fi и задайте пароль root.

### Обновление

LuCI → «Система → Резервная копия/Прошивка → Установить образ» с файлом `*-sysupgrade.bin`,
или из консоли:
```
sysupgrade -v /tmp/openwrt-qualcommbe-ipq53xx-xiaomi_rd16-squashfs-sysupgrade.bin
```
Обновление пишет только слот A, а U-Boot перед записью перенаправляется на него.
Файлы `factory.ubi` и `.itb` sysupgrade не принимает. Для варианта с podkop сначала
выполните `/etc/init.d/podkop stop`: образ копируется в /tmp, а это оперативная память.

### Возврат на заводскую прошивку

Из OpenWrt: `fw_setenv flag_boot_rootfs 1; reboot`, или из U-Boot: `setenv flag_boot_rootfs 1; saveenv; reset`.
Слот B при этом не меняется, а OpenWrt в слоте A остаётся. Вернуться в OpenWrt можно с заводской прошивки
(`nvram set flag_boot_rootfs=0; nvram commit; reboot`) или из U-Boot.

## Сборка

Нужна система GNU/Linux с регистрозависимой файловой системой. Подойдёт и WSL2, но дерево
OpenWrt должно лежать в файловой системе WSL, а не на `/mnt/c` или `/mnt/d`.

### Зависимости

Debian/Ubuntu (как в [документации OpenWrt](https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem)):
```
sudo apt install build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
  gettext git libncurses5-dev libssl-dev python3-setuptools rsync swig unzip zlib1g-dev \
  file wget python3 squashfs-tools pipx
pipx install ubi_reader
```
Под WSL в `/etc/wsl.conf` должно стоять `[interop] appendWindowsPath=false`, иначе сборка OpenWrt откажется работать.

### Прошивка Wi‑Fi из заводского образа

Прошивка Q6 и данные платы (`bdwlan`) — это бинарные файлы Qualcomm и Xiaomi, поэтому они
**не входят в репозиторий**. Калибровку роутер читает сам, из своего раздела ART.
Взять прошивку можно из одного из двух источников:

- **заводской системы своего роутера** (дамп слота B, см. «Установка», способ 2, шаг 2):
  ```
  ./scripts/extract-stock.sh rootfs_1.bin
  ```
- **официального файла прошивки Xiaomi для RD16** (`miwifi_rd16_firmware_*.bin`): дамп не нужен,
  ubi_reader сам находит UBI‑образ внутри контейнера Xiaomi (HDR1):
  ```
  ./scripts/extract-stock.sh miwifi_rd16_firmware_XXXX.bin
  ```

В обоих случаях результат будет в `stock/rootfs/lib/firmware`, и скрипт напишет версию
прошивки Q6. Порт проверен с `WLAN.WBE.1.3.r4-00038`. С другой версией скрипт предупредит:
она может потребовать других областей памяти или параметров загрузки Q6.
Прошивка для других устройств, например GL.iNet для 1 ГБ ОЗУ, на RD16 падает:
она рассчитана на другой режим памяти.

### Быстрый старт

```
git clone <этот репозиторий> openwrt-xiaomi-rd16 && cd openwrt-xiaomi-rd16
./scripts/extract-stock.sh /путь/к/rootfs_1.bin   # или miwifi_rd16_firmware_*.bin
bash build.sh                      # оба варианта; только один: VARIANTS=base bash build.sh
```
Скрипт сам клонирует дерево OpenWrt в `./openwrt` на нужном коммите, накладывает патчи,
обновляет фиды и собирает. Образы и логи складываются в `out/<вариант>/`.

Параметры передаются через переменные окружения:

| Переменная | По умолчанию | |
|---|---|---|
| `OPENWRT_DIR` | текущий каталог, если это дерево OpenWrt, иначе `./openwrt` | дерево OpenWrt |
| `STOCK_FW` | `./stock/rootfs/lib/firmware` | распакованный `lib/firmware` заводской системы |
| `OUT_DIR` | `./out` | куда класть образы |
| `VARIANTS` | `base podkop` | что собирать |
| `JOBS` | число CPU | параллельность make |
| `KEEP_TREE=1` | — | не сбрасывать дерево к базе с патчами (для своих правок) |

Скрипт можно запускать и из уже существующего дерева OpenWrt:
`cd ~/openwrt-rd16 && bash ~/openwrt-xiaomi-rd16/build.sh`.
Без `KEEP_TREE=1` он **сбросит дерево** (`git reset --hard`) к базовому коммиту и заново наложит патчи.

Первая сборка занимает несколько часов, в варианте `podkop` дольше: собирается компилятор Go.

## Устройство проекта

```
build.sh                  подготовка дерева, фиды, overlay, сборка вариантов
configs/                  xiaomi_rd16.config (base), xiaomi_rd16-podkop.config (добавка)
patches/                  серия для git am поверх fivefold3/openwrt-gl-be3600 @ e46ea77
scripts/extract-stock.sh  lib/firmware из дампа слота B или из прошивки Xiaomi (.bin)
scripts/stock-wifi-fw.py  заводская прошивка Q6 + board-2.bin -> files/lib/firmware
scripts/luci-wan-first.py порт WAN первым в строке портов LuCI (как на корпусе)
scripts/podkop-fixups.sh  правки фида podkop (зависимость sing-box, версия для apk, кэш версии)
```

| Патч | Что делает |
|---|---|
| 0001 | SPI‑NAND: поддержка W25N01KW, исправлен порядок SET_FEATURE в QPIC (без него все чтения давали ECC‑ошибки) |
| 0002 | Драйвер DSA Motorcomm YT921x из Linux 6.19: ожидание чипа после сброса, управление reset‑GPIO |
| 0003 | ath12k: режим памяти 256 МБ (QSDK mem‑mode 2) и уменьшенные кольца; выключаемое кольцо статуса монитора; управление потоком передачи |
| 0004 | Плата: DTS, образ UBI/FIT, sysupgrade в слот A, окружение U-Boot, сброс счётчика неудачных загрузок, RPS и раскладка прерываний, Wi‑Fi по умолчанию |
| 0005 | Кнопка mesh включает и выключает Wi‑Fi (`KEY_RFKILL`, обработчик `/etc/rc.button/rfkill`) |
| 0006 | Светодиод статуса как в стоке: синий — WAN поднят, оранжевый — WAN нет (`/etc/hotplug.d/iface/50-rd16-leds`, `/etc/init.d/rd16-leds`) |

### Параметры ath12k

`/etc/modules.d/ath12k`, например `ath12k rx_mon_status=1`:

- `rx_mon_status=-1|0|1` — кольцо статуса монитора. По умолчанию (−1) в режиме 256 МБ выключено.
  Включите (`1`), если нужен уровень сигнала и скорость приёма клиентов в LuCI;
  это стоит заметной доли одного ядра CPU при нагрузке.

## Сравнение с RomikB/openwrt (`openwrt-24-rd15`)

[RomikB/openwrt](https://github.com/RomikB/openwrt/tree/openwrt-24-rd15) поддерживает RD15 и RD16
другим способом: он берёт ядро и драйверы Qualcomm из QSDK, а бинарные пакеты — из заводской
прошивки Xiaomi. Ниже сравнение по исходникам ветки на коммите `a0ddd6f`. Скорость там не измерялась.

| | RomikB `openwrt-24-rd15` | этот проект |
|---|---|---|
| Основа | OpenWrt 24.10 | OpenWrt main (SNAPSHOT) |
| Ядро | QSDK `linux-ipq-5.4` (codelinaro) | Linux 6.18 |
| Пользовательское пространство | 32‑бит ARM (`cortex-a7`), как в заводской прошивке | 64‑бит `aarch64` |
| Wi‑Fi | проприетарный `qca-wifi` из заводской прошивки (cnss‑daemon, cfg80211tool, vendor hostapd/wpa_supplicant) | открытый ath12k, hostapd OpenWrt; из заводской прошивки взята только прошивка Q6 |
| Коммутатор | вендорский драйвер `yt-9215s` + swconfig | DSA `yt921x` из ядра (Linux 6.19) |
| Ускорение | NSS PPE/ECM (аппаратный NAT, ускорение Wi‑Fi) | нет: CPU, RPS, программный flow offload |
| Wi‑Fi‑функции | полный набор QSDK | HE80 на 5 ГГц; DFS и 160 МГц не работают |
| Откуда бинарники | генерируются из `miwifi_rd16_firmware_*.bin` (`vendor_scripts/`) | только прошивка Q6 и board data из дампа слота B |
| Слоты A/B, sysupgrade | ✅ | ✅ (только слот A, B — заводской) |
| Прокси и обход блокировок | профиль sing-box, forkop, AmneziaWG, zapret2 | вариант с podkop + sing-box, WireGuard |

Что выбрать:
- **RomikB** — если важны скорость маршрутизации через NSS и полный набор функций Wi‑Fi от Qualcomm,
  и вас устраивает вендорское ядро 5.4 с бинарными модулями из заводской прошивки.
- **Этот проект** — если нужно актуальное ядро и открытые драйверы, которые можно чинить и
  пересобирать, и не нужна скорость сверх ~600 Мбит/с на Wi‑Fi.

## Известные ограничения

- Linux видит ~170 МБ ОЗУ. ath12k забирает свою память при загрузке драйвера, а не при включении точки,
  поэтому выключение точки в LuCI память не освобождает.
- DFS‑каналы (52–144) и 160 МГц не работают: проверка на радары (CAC) то запускается, то нет, и точка не поднимается.
- Модули ядра (`kmod-*`) из официального репозитория OpenWrt к этому ядру не подходят.
  Всё нужное включайте в сборку.

## Лицензия

Патчи и скрипты распространяются, как и OpenWrt, под GPL‑2.0. Бинарные файлы прошивок Qualcomm
и Xiaomi в репозиторий не входят и не распространяются.
