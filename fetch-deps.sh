#!/bin/sh
# =============================================================================
# fetch-deps.sh — наполнить ./packages/ для офлайн-бандла SIP Registrar.
# =============================================================================
# Лёгкий бандл (≈13 МБ, 4 пакета):
#   - kamailio-6.1.1.pkg   — МИНИМАЛЬНАЯ сборка (без MySQL/XML/icu/libxml2),
#                            берётся из нашего GitHub Release (собрана CI на
#                            FreeBSD 14.0). НЕ из quarterly: тамошний kamailio
#                            тянет icu/libxml2 и ломает стоковый pfSense.
#   - rtpproxy + gsm       — из quarterly (ставятся на сток без конфликтов).
#   - pfSense-pkg-SipRegistrar-*.pkg — кладётся отдельно (py build_pkg.py).
#
# Запуск на pfSense 2.7.2 (amd64) С интернетом (нужен включённый pfSense-Extra).
# =============================================================================
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
PKGDIR="${HERE}/packages"
ABI="FreeBSD:14:amd64"
KAM_URL="https://github.com/humaxoid/SipRegistrar/releases/download/freebsd-pkgs/kamailio-6.1.1.pkg"

mkdir -p "${PKGDIR}"

echo "==> rtpproxy + gsm из quarterly ..."
env ABI="${ABI}" IGNORE_OSVERSION=yes ASSUME_ALWAYS_YES=yes \
    pkg fetch -d -y -o "${PKGDIR}" -r pfSense-Extra rtpproxy
# Сплющиваем All/Hashed -> packages/, оставляем только rtpproxy и gsm.
find "${PKGDIR}" -name 'rtpproxy-*.pkg' -o -name 'gsm-*.pkg' | while read -r f; do
    b=$(basename "$f" | sed 's/~[0-9a-f]*\.pkg$/.pkg/')
    [ -f "${PKGDIR}/$b" ] || cp "$f" "${PKGDIR}/$b"
done
rm -rf "${PKGDIR}/All" 2>/dev/null || true
# Убираем всё лишнее, если pkg fetch притащил другие зависимости.
for f in "${PKGDIR}"/*.pkg; do
    case "$(basename "$f")" in
        kamailio-*|rtpproxy-*|gsm-*|pfSense-pkg-SipRegistrar-*) : ;;
        *) rm -f "$f" ;;
    esac
done

echo "==> минимальный kamailio из GitHub Release ..."
fetch -o "${PKGDIR}/kamailio-6.1.1.pkg" "${KAM_URL}" \
    || curl -sL -o "${PKGDIR}/kamailio-6.1.1.pkg" "${KAM_URL}"

echo "==> генерирую SHA256SUMS (контроль целостности для install.sh)..."
# our-пакет должен быть уже скопирован сюда (build_pkg.py + cp) ДО этого шага.
( cd "${PKGDIR}" && sha256 -r *.pkg > SHA256SUMS ) 2>/dev/null \
    && echo "    SHA256SUMS создан" \
    || echo "    (sha256 недоступен — SHA256SUMS не создан)"

echo "==> готово, в packages/:"
ls -1 "${PKGDIR}"/*.pkg
echo "    (если pfSense-pkg-SipRegistrar-*.pkg добавили ПОСЛЕ — перегенерируйте SHA256SUMS:"
echo "     cd packages && sha256 -r *.pkg > SHA256SUMS)"
