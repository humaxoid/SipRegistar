#!/bin/sh
# =============================================================================
# pfSense-pkg-SipRegistrar — ОФЛАЙН-УСТАНОВЩИК (без доступа в интернет)
# =============================================================================
# Все пакеты (kamailio, rtpproxy и все их зависимости + сам SIP Registrar)
# лежат в ./packages/. Установка идёт ТОЛЬКО из этого локального репозитория —
# ничего не скачивается из сети.
#
# Запуск на целевом pfSense 2.7.2 (amd64):
#     sh /path/to/offline/install.sh
#
# Идемпотентно: повторный запуск не ломает уже установленное.
# Удаление:  pkg delete pfSense-pkg-SipRegistrar   (см. также ../uninstall.sh)
# =============================================================================
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
PKGDIR="${HERE}/packages"
ABI="FreeBSD:14:amd64"
REPOS_DIR="/tmp/sipreg-offline-repos"

echo "==> SIP Registrar: офлайн-установка из ${PKGDIR}"

if [ ! -d "${PKGDIR}" ]; then
    echo "ОШИБКА: нет каталога packages/. Заполните его (см. fetch-deps.sh)." >&2
    exit 1
fi
_n=$(ls -1 "${PKGDIR}"/*.pkg 2>/dev/null | wc -l | tr -d ' ')
if [ "${_n}" = "0" ]; then
    echo "ОШИБКА: в packages/ нет ни одного .pkg. Заполните (fetch-deps.sh)." >&2
    exit 1
fi
echo "    Найдено пакетов: ${_n}"

# 0a. Проверка целостности пакетов (sha256), если есть SHA256SUMS.
if [ -f "${PKGDIR}/SHA256SUMS" ]; then
    echo "==> Проверка целостности (sha256)..."
    _bad=0
    while read -r _want _file; do
        [ -n "${_want}" ] || continue
        if [ ! -f "${PKGDIR}/${_file}" ]; then
            echo "    ОШИБКА: нет файла ${_file}" >&2; _bad=1; continue
        fi
        _have=$(sha256 -q "${PKGDIR}/${_file}" 2>/dev/null)
        if [ "${_have}" != "${_want}" ]; then
            echo "    ОШИБКА: хэш не совпал для ${_file}" >&2; _bad=1
        fi
    done < "${PKGDIR}/SHA256SUMS"
    if [ "${_bad}" != "0" ]; then
        echo "ОШИБКА: проверка целостности не пройдена. Установка прервана." >&2
        exit 1
    fi
    echo "    целостность OK"
else
    echo "    (SHA256SUMS нет — проверка целостности пропущена)"
fi

# 0b. Предупреждение, если SIP-порт 5060 уже занят другим сервисом (напр. FreeSWITCH).
if sockstat -4 -l 2>/dev/null | grep -qE "[:.]5060\b"; then
    _who=$(sockstat -4 -l 2>/dev/null | grep -E "[:.]5060\b" | grep -v kamailio | awk '{print $2}' | sort -u | tr '\n' ' ')
    if [ -n "${_who}" ]; then
        echo "    ВНИМАНИЕ: порт 5060 уже занят (${_who}). Если это не kamailio —"
        echo "    смените SIP Port в GUI (Services -> SIP Registrar -> Settings) после установки."
    fi
fi

# 1. ASLR НЕ отключаем. Раньше отключали глобально (Kamailio 6.x с KEMI падал при
#    ASLR), но наша МИНИМАЛЬНАЯ сборка без KEMI работает с ASLR включённым
#    (проверено) — система остаётся защищённой. Очистку возможного старого
#    глобального отключения делает POST_INSTALL пакета.

# 2. Строим каталог локального репозитория из вложенных .pkg.
echo "==> Готовлю локальный репозиторий (pkg repo)..."
env ABI="${ABI}" IGNORE_OSVERSION=yes pkg repo "${PKGDIR}" >/dev/null

# 3. Временный конфиг репозитория, указывающий ТОЛЬКО на локальный каталог.
#    Через -o REPOS_DIR pkg будет использовать исключительно его (без сети).
#    ВАЖНО: имя репозитория = "pfSense". pfSense GUI (pkg_mgr_installed.php →
#    get_pkg_info) показывает в «Installed Packages» ТОЛЬКО пакеты, у которых
#    repository (%R) == "pfSense". Ставя из репо с этим именем, мы получаем
#    %R=pfSense → пакет виден в менеджере. (Реальный pfSense-репо Netgate лежит
#    в другом каталоге и здесь не используется — конфликта нет.)
mkdir -p "${REPOS_DIR}"
cat > "${REPOS_DIR}/pfSense.conf" <<EOF
pfSense: {
    url: "file://${PKGDIR}",
    enabled: yes
}
EOF

# 4. Устанавливаем наш пакет с зависимостями ТОЛЬКО из локального репозитория.
#    -o REPOS_DIR=... ограничивает pkg нашим каталогом (сеть не используется).
#    Зависимости — это МИНИМАЛЬНЫЙ kamailio (без icu/libxml2/mysql), rtpproxy и
#    gsm; они НЕ требуют обновления базовых библиотек pfSense (проверено dry-run).
echo "==> Устанавливаю pfSense-pkg-SipRegistrar + зависимости (без сети)..."
env ABI="${ABI}" IGNORE_OSVERSION=yes ASSUME_ALWAYS_YES=yes \
    pkg -o REPOS_DIR="${REPOS_DIR}" -o IGNORE_OSVERSION=yes \
    install pfSense-pkg-SipRegistrar

# 5. Чистим временный конфиг репозитория.
rm -rf "${REPOS_DIR}" 2>/dev/null || true

echo ""
echo "==> Готово. Проверьте:"
echo "    System > Package Manager > Installed Packages  (pkg_mgr_installed.php)"
echo "    System > Services > SIP Registrar"
echo ""
echo "    Статус сервиса:  /usr/local/bin/sip_registrar_ctl.sh status"
echo "    Удаление:        pkg delete pfSense-pkg-SipRegistrar"
exit 0
