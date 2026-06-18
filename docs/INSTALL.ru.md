# Инструкция по установке — pfSense-pkg-SipRegistrar v2.4.0

Руководство по установке SIP Registar (**Kamailio 6.1.1** + **rtpproxy**) на
pfSense 2.7.2 **офлайн-способом** — без доступа в интернет на самом pfSense и **без
обновления/повреждения базовой системы**.

> **Требования**:
> - pfSense **2.7.2-RELEASE**, архитектура **amd64** (FreeBSD 14)
> - SSH/консольный доступ к pfSense (root / учётка `admin`)
> - Возможность скопировать папку на pfSense (WinSCP/SFTP/USB)
> - Интернет на pfSense **НЕ требуется** (всё в бандле)
> - PuTTY настроен на UTF-8 (*Window → Translation → Remote character set: UTF-8*)

> Английская версия: [INSTALL.md](INSTALL.md)

---

## 1. Установка пакета — офлайн через `install.sh` (рекомендуется)

Бандл (папка `offline/`, ≈13 МБ) содержит сам пакет и все зависимости:

```
offline/
├── install.sh          # установщик
└── packages/
    ├── pfSense-pkg-SipRegistrar-2.4.0.pkg   # сам пакет
    ├── kamailio-6.1.1.pkg                   # минимальная сборка (без icu/libxml2)
    ├── rtpproxy-2.1.1_1.pkg                 # медиа‑прокси (RTP)
    └── gsm-1.0.23.pkg                       # кодек (зависимость rtpproxy)
```

> Минимальный `kamailio` собран так, чтобы линковаться **только с базовыми
> библиотеками FreeBSD** и НЕ тянуть `icu`/`libxml2`/`mysql`. Поэтому установка
> ничего не обновляет в базе pfSense и ничего из неё не удаляет.

### Шаг 1. Скопировать папку `offline/` на pfSense

С Windows (PowerShell, через SCP):
```powershell
scp -r "C:\path\to\pfSense-pkg-SipRegistrar\offline" admin@LAN_IP:/root/offline
```
Или загрузите папку `offline` целиком в `/root/` через WinSCP/FileZilla.

В итоге на pfSense должно быть: `/root/offline/install.sh` и `/root/offline/packages/*.pkg`.

### Шаг 2. Подключиться по SSH и запустить

Host: IP pfSense, Port: 22. В меню pfSense — **8) Shell** (или Diagnostics →
Command Prompt). Затем:

```sh
cd /root/offline
sh install.sh
```

Скрипт выполнит автоматически:
1. оставит системный ASLR **включённым** (минимальная сборка kamailio без KEMI в
   нём не нуждается) и уберёт старое глобальное отключение, если оно было;
2. соберёт локальный репозиторий с именем **`pfSense`** — важно, иначе пакет не
   будет виден в Package Manager (см. «Важные замечания» ниже);
3. поставит 4 пакета **только из локального каталога** (без сети, без обновления базы);
4. сгенерирует рабочий `kamailio.cfg` и **сразу запустит** `kamailio` + `rtpproxy`.

Признак успеха:
```
[4/4] Installing pfSense-pkg-SipRegistrar-2.4.0...
apply ok
  SIP Registrar installed successfully.
==> Готово.
```

> ⚠ Рекомендуется заранее сделать backup конфига pfSense
> (*Diagnostics → Backup & Restore → Download configuration*).

Скрипт пост-установки также: создаёт пользователя/группу `kamailio`, ставит права на
`dbtext/`, включает автозагрузку, инициализирует раздел `<sipregistrar>` в `config.xml`
и регистрирует пакет в Package Manager и меню Services.

---

## 1a. После установки: проверка и доступ в GUI

**Проверка по SSH:**
```sh
pkg info pfSense-pkg-SipRegistrar | head -3      # пакет установлен
pkg query '%R' pfSense-pkg-SipRegistrar          # должно быть: pfSense (кавычки '%R' — для tcsh)
ps ax | grep -E '[k]amailio|[r]tpproxy'          # сервисы запущены
/usr/local/sbin/kamailio -f /usr/local/etc/kamailio/kamailio.cfg -c; echo "exit=$?"  # exit=0
```

**В веб‑интерфейсе** (обновите страницу — **Ctrl+F5**, при необходимости перезайдите):
- **System → Package Manager → Installed Packages** — появляется `SIP Registrar 2.4.0`.
- **Services → SIP Registrar** — страница настройки.
- **Дашборд‑виджет:** на главной (Dashboard) нажмите **«+»** (Available Widgets) и
  добавьте **SIP Registrar**. *(Виджеты в pfSense добавляются вручную.)*

### Важные замечания
- **Имя репозитория `pfSense`.** Страница «Installed Packages» показывает только
  пакеты, у которых `pkg query %R` = `pfSense`. Установщик специально создаёт
  локальный репозиторий с этим именем (через `-o REPOS_DIR`). Репозиторий Netgate
  при этом не используется — конфликта нет, `pkg upgrade` пакет не трогает.
- **База pfSense не меняется.** `pfSense`, `php82`, `kea` остаются на месте —
  добавляются только `kamailio`, `rtpproxy`, `gsm` и сам пакет.
- **ASLR НЕ отключается** — защита системы сохраняется. Минимальная сборка kamailio
  (без KEMI) работает с ASLR включённым; если прежняя версия глобально отключала
  ASLR (`kern.elf64.aslr.*` в sysctl/Tunables), установщик это очищает.
- **Логи.** Kamailio пишет в **`/var/log/SipRegistrar.log`** (напрямую, минуя
  pfSense‑syslog — там `local0.none` отбрасывает логи). Ротация — `newsyslog`
  (ежедневно / 5 МБ / хранить 14 / gzip), правило в
  `/var/etc/newsyslog.conf.d/SipRegistrar.log.conf`. Подробность логов — *Services →
  SIP Registrar → Settings → Log Level* (0–3; для продакшена 1, для диагностики 3).
  Лог rtpproxy/старта — `/var/log/kamailio_start.log`.

---

## 2. Открытие SIP-порта в брандмауэре

Пакет НЕ изменяет правила брандмауэра автоматически. Правило нужно
добавить вручную.

1. Перейдите в *Firewall → Rules → LAN → Add* (стрелка вверх).
2. Заполните:
   - **Action**: Pass
   - **Interface**: LAN
   - **Protocol**: UDP
   - **Source**: LAN net
   - **Destination**: This Firewall (или LAN address)
   - **Destination Port Range**: SIP-порт из настроек (по умолчанию 5060)
   - **Description**: `Allow SIP to Kamailio Registrar`
3. Сохраните и примените.

> ** Если Вы не используете SIP Trunk, то не открывайте SIP с WAN.** В этом пакете нет защиты от
> brute-force-атак или DDoS из Интернета. Если-же SIP Trunk задействован, то создайте входящее правило
> разрешающее доступ по UDP порту 5060, только для вашего VoIP провайдера.

4. Перейдите в *Firewall → Rules → WAN → Add* (стрелка вверх).
5. Заполните:
   - **Action**: Pass
   - **Interface**: WAN
   - **Protocol**: UDP
   - **Source**: IP вашего SIP провайдера
   - **Destination**: This Firewall
   - **Destination Port Range**: SIP-порт из настроек (по умолчанию 5060)
   - **Description**: `Allow SIP to Kamailio Registrar`
6. Сохраните и примените.

---

## 3. Настройка регистратора

Откройте *Services → SIP Registrar*.

### Вкладка Settings

| Поле        | По умолчанию           | Примечание                                    |
|-------------|------------------------|-----------------------------------------------|
| SIP Port    | 5060                   | UDP-порт (1024..65535)                        |
| SIP Realm   | авто LAN IP            | Realm для SIP-аутентификации                  |
| Log Level   | 1 (Warnings)           | 0..3, уровень 3 — только для диагностики      |
| Language    | English                | Язык интерфейса (также сохраняется в браузере)|

> **Внимание**: смена SIP Realm делает недействительными все HA1-хеши.
> После смены придётся заново ввести пароль для каждого устройства.

### Вкладка Gateways

Добавьте каждый внешний SIP-шлюз как строку:

| Поле           | Примечание                                              |
|----------------|---------------------------------------------------------|
| Gateway IP     | IPv4-адрес шлюза                                        |
| Port           | SIP-порт шлюза (по умолчанию 5060)                      |
| Prefix         | Начальные цифры набираемого номера, либо пусто          |
| Description    | Произвольный текст (напр. "Yeastar TA800 PSTN")         |
| Priority       | 1 (высокий) .. 3 (низкий)                               |

Логика маршрутизации:
- При новом INVITE сначала ищется алиас Number → SIP ID. Если телефон
  зарегистрирован, звонок идёт peer-to-peer.
- Если не зарегистрирован, перебираются шлюзы с подходящим префиксом
  в порядке приоритета; длинный префикс побеждает короткий.
- Шлюз с **пустым префиксом** — маршрут по умолчанию, используется,
  когда другие не подходят.

### Вкладка Devices

Добавьте каждый телефон или программный клиент:

| Поле          | Примечание                                              |
|---------------|---------------------------------------------------------|
| Number        | Номер для набора (2..5 цифр, напр. 101)                 |
| IP Address    | Опционально — только для справки                        |
| SIP ID        | Имя регистрации (буквы/цифры/`_.-`, 1..64)              |
| SIP Password  | Обязательно для нового устройства                       |
| Type          | Авто-определение: Phone (IP) или Gateway (SIP)          |
| Description   | Произвольный текст (напр. "alice (sales department)")   |

После добавления/правки всех записей нажмите **Сохранить**.
Kamailio перезагрузит конфиг без обрыва активных звонков.

### Вкладка Trunks (Транки)

Добавьте линии внешних SIP-провайдеров. Kamailio регистрируется как UAC-клиент.

| Поле        | Описание                                                   |
|-------------|-------------------------------------------------------------|
| Телефон/DID | Номер от провайдера (напр. +7XXXXXXXXXX)                    |
| SIP Домен   | Домен SIP провайдера (напр. sip.provider.ru)                |
| Proxy IP    | IP-адрес SIP-прокси провайдера                              |
| Порт        | Порт SIP-прокси (по умолчанию 5060)                         |
| Логин       | Имя пользователя для регистрации                            |
| Пароль      | Пароль для регистрации                                      |
| Вкл         | Включить/выключить транк                                    |
| Описание    | Произвольный текст (напр. «Основная линия»)                 |

Расширенные настройки (клик по строке → панель «Расширенные»): таймеры Expires, Interval, Keep-Alive.

Бейджи статуса обновляются каждые 5 секунд: Registered (зелёный), Offline (серый), Failed (красный).

### Вкладка Incoming (Входящие)

Настройте маршрутизацию входящих звонков от транков/шлюзов к внутренним добавочным.
Для каждого DID можно задать дневной и ночной номер, рабочие часы и дни.

### Вкладка Outbound (Исходящие)

Настройте какие добавочные могут совершать исходящие звонки через каждый транк или шлюз.
Неуказанные номера получают ошибку 403 Forbidden.

---

## 4. Настройка SIP-телефонов

Названия пунктов меню зависят от производителя, но параметры одинаковы:

| Параметр                          | Значение                                       |
|-----------------------------------|------------------------------------------------|
| SIP Server                        | LAN IP pfSense                                 |
| SIP Port                          | Как в Settings (по умолчанию 5060)             |
| Authentication / Username         | SIP ID из таблицы Devices                      |
| Authentication / Password         | SIP Password из таблицы Devices                |
| Display name                      | Любой текст                                    |
| Transport                         | UDP                                            |
| Период регистрации (Re-REGISTER)  | 60..3600 секунд (значение по умолчанию подойдёт)|

### Пример: Grandstream GRP2601P

1. Веб-интерфейс → *Accounts → Account 1 → General Settings*
2. Account Name = `alice`
3. SIP Server = (LAN IP pfSense)
4. SIP User ID = `alice` (SIP ID из Devices)
5. Authenticate ID = `alice`
6. Authenticate Password = пароль, введённый в pfSense
7. Save and apply

### Пример: Zoiper

1. Settings → Accounts → Add Account → SIP
2. Domain = `lan_ip`
3. Username = `alice`
4. Password = пароль из pfSense

---

## 5. Настройка SIP-шлюзов

Внешние шлюзы (Yeastar TA800, Grandstream GXW, Asterisk и др.) могут
регистрироваться на pfSense, как и обычные SIP-устройства. Либо
оставьте их без регистрации, если доступны по статическому IP — в
этом случае pfSense обращается к ним по IP, указанному во вкладке
Gateways.

Если шлюз должен регистрироваться:
- Создайте запись Device с SIP ID, содержащим одно из ключевых слов:
  `gw`, `gateway`, `trunk`, `pstn`, `ta800`, `yeastar` и др. — тип
  будет автоматически определён как Gateway (SIP).
- На шлюзе укажите `SIP Server = LAN IP pfSense`, `Username = SIP ID`,
  `Password = SIP Password`.

---

## 6. Проверка работы

```sh
# Активные регистрации
kamcmd ul.dump

# Алиасы Number → SIP ID
kamcmd alias.dump

# Статистика транзакций
kamcmd tm.stats

# Версия Kamailio
kamcmd core.version

# Статус сервиса
service kamailio status

# Прослушиваемые порты
sockstat -4 -l | grep 5060
```

Вкладка Status в веб-интерфейсе показывает ту же информацию визуально.

---

## 7. Обновление

Кнопка **Update** в Package Manager для этого пакета не работает (его нет в
репозитории Netgate). Обновление = повторный запуск установщика с новым бандлом:
```sh
cd /root/offline        # папка с новыми .pkg
sh install.sh
```
Настройки в `<sipregistrar>` (`config.xml`) при этом **сохраняются**.

---

## 8. Удаление

Через GUI: *System → Package Manager → Installed Packages → Remove* рядом с
`pfSense-pkg-SipRegistrar`.

Через SSH:
```sh
# Только пакет (зависимости останутся)
pkg delete -y pfSense-pkg-SipRegistrar

# Полностью, вместе с kamailio/rtpproxy/gsm
pkg delete -y pfSense-pkg-SipRegistrar kamailio rtpproxy gsm
pkg autoremove -y
```

При удалении: останавливаются сервисы Kamailio и rtpproxy, снимается автозагрузка,
чистятся cron/ротация логов. Проверено: базовая система pfSense (`php82`, `kea`,
метапакет `pfSense`) остаётся **целой**.

---

## 9. Мониторинг и отладка

### Мониторинг (по SSH)
```sh
kamcmd ul.dump                 # активные регистрации (телефоны/транки)
kamcmd tm.stats                # статистика транзакций (вкл. активные)
kamcmd dlg.list                # активные диалоги (звонки); число: dlg.stats_active
kamcmd core.uptime             # аптайм/версия движка
sockstat -4 -l | grep 5060     # слушающие SIP-сокеты
top -b 10 | grep -i kamailio   # нагрузка процессов kamailio (или интерактивно: top)
```

### Логи
- Файл: **`/var/log/SipRegistrar.log`** (ротация newsyslog — см. §1a).
- Уровень: *Services → SIP Registrar → Settings → Log Level* (1 — продакшен, 3 — диагностика).

### Отладка SIP-трафика (tcpdump)
На FreeBSD/pfSense: указывайте **конкретный интерфейс** (псевдо‑`any` НЕ работает),
используйте **`-U`** (без буферизации, иначе мелкий захват «не пишется») и
фильтруйте **по портам, а не по host** (по host теряется RTP с других адресов):
```sh
ifconfig | grep -E "^[a-z]|inet "                 # узнать имена интерфейсов (LAN/WAN)
# сигнализация + медиа на LAN (пример re0):
tcpdump -n -s0 -U -i re0 -w /tmp/sip.pcap port 5060 or portrange 10000-40000
# обмен с провайдером на WAN (пример bge0):
tcpdump -n -s0 -U -i bge0 -w /tmp/trunk.pcap host <IP_провайдера>
```
Удобнее снять через GUI: *Diagnostics → Packet Capture*. Файл `.pcap` открыть в Wireshark.

### Частые вопросы по безопасности/совместимости
- **ASLR** не отключается (см. §1a) — система защищена.
- **MAC/SELinux**: SELinux на FreeBSD нет; MAC‑фреймворк (`mac_bsdextended`) в
  pfSense 2.7.2 по умолчанию **выключен** — Kamailio он не блокирует.
- **Целостность пакетов**: `install.sh` сверяет `packages/SHA256SUMS` перед установкой.

При проблемах смотрите `TROUBLESHOOTING.ru.md`.
