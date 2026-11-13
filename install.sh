#!/bin/sh
# =============================================================================
#  AutoBiss E2 — Smart Installer for Enigma2 receivers
#
#  The script inspects the receiver first and then installs the package that
#  matches it:
#     * receiver model  (Dreambox, VU+, Zgemma, Axasis, ...)
#     * image           (OpenATV, OpenPLi, OpenDreambox/OE-core, OpenViX, ...)
#     * package manager (real opkg -> .ipk , apt/dpkg -> .deb)
#     * CPU arch        (aarch64 / arm / mips / mipsel)
#     * Python version  (2.7 or 3.x, the plugin supports both)
#
#  Usage:
#     wget -O - https://raw.githubusercontent.com/OWNER/REPO/main/install.sh | sh
#     curl -sSL https://raw.githubusercontent.com/OWNER/REPO/main/install.sh | sh
#
#  Options:
#     --check           only detect the receiver/image, install nothing
#     --version <ver>   plugin version to install (default: 3.7.5)
#     --repo <o/r>      GitHub repository holding the release assets
#     --url <base-url>  explicit base URL for the package files
#     --local <file>    install a package that is already on the receiver
#     --uninstall       remove the plugin
#     --yes             do not ask for confirmation
#     --help            this text
#
#  Exit codes: 0 ok, 1 error, 2 unsupported receiver
# =============================================================================

PLUGIN_VERSION="3.7.5"
DEFAULT_REPO="prof-abdo/autobiss-e2"
DEFAULT_TAG="v3.0"
MIRROR_URL="https://tsdec.kingcs.xyz/autobiss"

REPO=""
BASE_URL=""
LOCAL_PKG=""
DO_CHECK=0
DO_UNINSTALL=0
ASSUME_YES=0

# ── Output helpers ────────────────────────────────────────────────────────────
if [ -t 1 ]; then
    R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; N='\033[0m'
else
    R=''; G=''; Y=''; B=''; N=''
fi
info() { echo "${B}[*]${N} $*"; }
ok()   { echo "${G}[+]${N} $*"; }
warn() { echo "${Y}[!]${N} $*"; }
err()  { echo "${R}[-]${N} $*" >&2; }
die()  { err "$*"; exit 1; }

# ── Arguments ─────────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --check)      DO_CHECK=1; shift ;;
        --version)    PLUGIN_VERSION="${2:-}"; shift 2 ;;
        --repo)       REPO="${2:-}"; shift 2 ;;
        --url)        BASE_URL="${2:-}"; shift 2 ;;
        --local)      LOCAL_PKG="${2:-}"; shift 2 ;;
        --uninstall)  DO_UNINSTALL=1; shift ;;
        --yes|-y)     ASSUME_YES=1; shift ;;
        --help|-h)    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)            die "unknown option: $1  (try --help)" ;;
    esac
done

[ "$(id -u)" = "0" ] || die "please run as root: su -c \"$0 $*\""

# ── 1. Receiver / image detection ────────────────────────────────────────────
IMAGE="Unknown"
IMAGE_VER=""
MODEL="Unknown"
PKGMGR=""
FORMAT=""
ARCH="$(uname -m)"
PY_VER=""
DT_MODEL=""
DT_COMPAT=""

detect_model() {
    DT_MODEL=""
    DT_COMPAT=""
    if [ -r /proc/device-tree/model ]; then
        DT_MODEL="$(tr -d '\000' < /proc/device-tree/model 2>/dev/null)"
    fi
    if [ -r /proc/device-tree/compatible ]; then
        DT_COMPAT="$(tr -d '\000' < /proc/device-tree/compatible 2>/dev/null | tr '\n' ' ')"
    fi

    if [ -f /etc/opkg/platform ]; then
        MODEL="$(tr -d '\000' < /etc/opkg/platform 2>/dev/null)"
    fi

    HOST="$(hostname 2>/dev/null)"
    case "$HOST" in
        dreambox*|dm*)
            if [ -n "$DT_MODEL" ]; then
                case "$DT_COMPAT$DT_MODEL" in
                    *g12b*|*Amlogic*) MODEL="dreambox-two" ;;
                esac
            fi
            [ -n "$MODEL" ] || MODEL="dreambox"
            ;;
        vuplus*|vu+) [ -n "$MODEL" ] || MODEL="vuplus" ;;
    esac

    # OpenDreambox / OE-core style boxes
    if [ "$MODEL" = "Unknown" ] && echo "$DT_MODEL" | grep -qi 'dream\|vuplus\|Zgemma'; then
        MODEL="$DT_MODEL"
    fi
    if [ "$MODEL" = "Unknown" ] && [ -n "$HOST" ] && [ "$HOST" != "localhost" ]; then
        MODEL="$HOST"
    fi
}

detect_image() {
    # 1) explicit release markers
    for f in /etc/openatv-release /etc/openpli-release /etc/openvix-release \
             /etc/coreelec-release /etc/oe-release; do
        if [ -f "$f" ]; then
            IMAGE="$(head -n 1 "$f" 2>/dev/null | tr -d '\r')"
            [ -n "$IMAGE" ] && return
        fi
    done

    # 2) apt/dpkg based images (OpenDreambox, OpenATV 8/9, OpenPLi 8)
    if command -v dpkg-query >/dev/null 2>&1; then
        IMAGE_VER="$(dpkg-query -W -f='${Version}' enigma2 2>/dev/null)"
        if [ -n "$IMAGE_VER" ]; then
            SRC="$(grep -rhs -m1 -E 'opendreambox|openatv|openpli|openvix|oe-core' \
                   /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null)"
            case "$IMAGE_VER$SRC" in
                *opendreambox*|*oe-core*) IMAGE="OpenDreambox / OE-core" ;;
                *openatv*)               IMAGE="OpenATV (apt)" ;;
                *openpli*)               IMAGE="OpenPLi (apt)" ;;
                *openvix*)               IMAGE="OpenViX (apt)" ;;
                *)                       IMAGE="OE-core (apt)" ;;
            esac
            return
        fi
    fi

    # 3) real opkg based images (OpenATV 6/7, OpenPLi 7, ...)
    if command -v opkg >/dev/null 2>&1; then
        IMAGE_VER="$(opkg status enigma2 2>/dev/null | sed -n 's/^Version: //p' | head -n 1)"
        case "$IMAGE_VER" in
            *openatv*) IMAGE="OpenATV (opkg)" ;;
            *openpli*) IMAGE="OpenPLi (opkg)" ;;
            *openvix*) IMAGE="OpenViX (opkg)" ;;
            *oe-core*) IMAGE="OE-core (opkg)" ;;
            "")        IMAGE="Enigma2 (opkg)" ;;
            *)         IMAGE="Enigma2 (opkg)" ;;
        esac
    fi
}

detect_pkgmgr() {
    # Prefer dpkg when this really is a debian-based Enigma2 image (DreamOS,
    # OpenATV 8+, OpenPLi 8+).  Some of them ship an opkg->apt shim whose
    # --version string is misleading, so query the enigma2 package instead.
    if command -v dpkg >/dev/null 2>&1 && dpkg -s enigma2 >/dev/null 2>&1; then
        PKGMGR="dpkg"; FORMAT="deb"; return
    fi
    if command -v opkg >/dev/null 2>&1; then
        PKGMGR="opkg"; FORMAT="ipk"; return
    fi
    if command -v dpkg >/dev/null 2>&1; then
        PKGMGR="dpkg"; FORMAT="deb"; return
    fi
    PKGMGR="none"; FORMAT=""
}

detect_python() {
    for p in python3 python2 python; do
        if command -v "$p" >/dev/null 2>&1; then
            V="$("$p" --version 2>&1 | head -n 1)"
            case "$V" in
                Python\ 3*) PY_VER="$V"; return ;;
                Python\ 2*) PY_VER="$V"; return ;;
            esac
        fi
    done
}

detect_model
detect_image
detect_pkgmgr
detect_python

PKG_NAME="enigma2-plugin-extensions-autobiss_${PLUGIN_VERSION}_all"
PLUGIN_DIR="/usr/lib/enigma2/python/Plugins/Extensions/AutoBiss"

echo ""
echo "  AutoBiss E2 installer  —  receiver report"
echo "  --------------------------------------------"
printf '  %-16s %s\n' "Receiver"  "$MODEL"
printf '  %-16s %s\n' "Image"     "$IMAGE${IMAGE_VER:+  ($IMAGE_VER)}"
printf '  %-16s %s\n' "SoC"       "${DT_MODEL:-unknown}${DT_COMPAT:+ / $DT_COMPAT}"
printf '  %-16s %s\n' "Arch"      "$ARCH"
printf '  %-16s %s\n' "Python"    "${PY_VER:-not found}"
printf '  %-16s %s\n' "Pkg mgr"   "$PKGMGR  ->  .${FORMAT:-?}"
printf '  %-16s %s\n' "Enigma2"   "$([ -d /usr/lib/enigma2 ] && echo present || echo MISSING)"
echo ""

# ── Sanity checks ─────────────────────────────────────────────────────────────
[ -d /usr/lib/enigma2 ] || die "no Enigma2 found on this system — is this really a receiver?"

if [ "$DO_CHECK" = "1" ]; then
    ok "check only, nothing installed"
    exit 0
fi

if [ "$DO_UNINSTALL" = "1" ]; then
    info "removing AutoBiss E2 ..."
    if [ "$PKGMGR" = "dpkg" ]; then
        dpkg --remove enigma2-plugin-extensions-autobiss 2>/dev/null || true
    elif [ "$PKGMGR" = "opkg" ]; then
        opkg remove enigma2-plugin-extensions-autobiss 2>/dev/null || true
    fi
    rm -rf "$PLUGIN_DIR"
    rm -rf /usr/lib/enigma2/python/Plugins/Extensions/AutoBiss
    rm -f /tmp/enigma2_plugins.xml
    echo ""
    ok "AutoBiss E2 removed — restart Enigma2 to apply"
    exit 0
fi

if [ "$PKGMGR" = "none" ]; then
    err "no supported package manager found (need opkg or dpkg)"
    exit 2
fi

# ── 2. Get the package ───────────────────────────────────────────────────────
TMPDIR_="/tmp/autobiss_install"
rm -rf "$TMPDIR_"
mkdir -p "$TMPDIR_"
cd "$TMPDIR_" || die "cannot create $TMPDIR_"

download() {
    URL="$1"; OUT="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$OUT" "$URL" && return 0
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -q -O "$OUT" "$URL" && return 0
    fi
    return 1
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$1" | awk '{print $NF}'
    else
        echo ""
    fi
}

PKG_FILE=""
if [ -n "$LOCAL_PKG" ]; then
    [ -f "$LOCAL_PKG" ] || die "local package not found: $LOCAL_PKG"
    PKG_FILE="$LOCAL_PKG"
    info "using local package $PKG_FILE"
else
    # Build the list of candidate base URLs
    CANDIDATES=""
    if [ -n "$BASE_URL" ]; then
        CANDIDATES="$BASE_URL"
    else
        R_OWNER="${REPO:-$DEFAULT_REPO}"
        R_OWNER="${R_OWNER%%/*}"
        R_NAME="${REPO##*/}"
        [ -n "$R_NAME" ] || R_NAME="autobiss-e2"
        TAG="${DEFAULT_TAG}"
        TAG="$TAG" # keep tag in sync with version unless overridden
        TAG="v${PLUGIN_VERSION}"
        CANDIDATES="https://github.com/${R_OWNER}/${R_NAME}/releases/download/${TAG}
https://raw.githubusercontent.com/${R_OWNER}/${R_NAME}/main/releases
https://raw.githubusercontent.com/${R_OWNER}/${R_NAME}/main
${MIRROR_URL}"
    fi

    FILE_NAME="${PKG_NAME}.${FORMAT}"
    info "downloading ${FILE_NAME} (${FORMAT}) ..."
    for C in $CANDIDATES; do
        C="$(echo "$C" | sed 's/[[:space:]]*$//')"
        U="${C%/}/${FILE_NAME}"
        if download "$U" "$FILE_NAME"; then
            PKG_FILE="$TMPDIR_/$FILE_NAME"
            ok "downloaded from $C"
            break
        fi
        warn "not available at $C"
    done
    [ -n "$PKG_FILE" ] || die "could not download ${FILE_NAME} — check network or use --local"

    # checksum verification (when a SHA256SUMS file is published next to it)
    for C in $CANDIDATES; do
        C="$(echo "$C" | sed 's/[[:space:]]*$//')"
        if download "${C%/}/SHA256SUMS" "SHA256SUMS" 2>/dev/null; then
            EXPECT="$(grep " ${FILE_NAME}\$" "SHA256SUMS" | head -n 1 | cut -d' ' -f1)"
            if [ -n "$EXPECT" ]; then
                ACTUAL="$(sha256_of "$PKG_FILE")"
                if [ -z "$ACTUAL" ]; then
                    warn "no sha256 tool available, skipping checksum"
                elif [ "$EXPECT" = "$ACTUAL" ]; then
                    ok "sha256 verified"
                else
                    die "checksum mismatch for $FILE_NAME — aborting"
                fi
            fi
            break
        fi
    done
fi

# ── 3. Install ───────────────────────────────────────────────────────────────
echo ""
info "installing $PKG_FILE ..."

# Some package managers do not create parent directories that are missing from
# the archive, so make sure the plugin folder exists before unpacking.
mkdir -p /usr/lib/enigma2/python/Plugins/Extensions 2>/dev/null || true

if [ "$PKGMGR" = "dpkg" ]; then
    # drop a previous half-installed state so dpkg can install cleanly
    dpkg --remove --force-all enigma2-plugin-extensions-autobiss >/dev/null 2>&1 || true
    if ! dpkg -i "$PKG_FILE" 2>&1; then
        warn "dpkg reported a problem, retrying with --force-depends"
        dpkg -i --force-depends --force-overwrite "$PKG_FILE" 2>&1 || true
    fi
    dpkg --configure -a >/dev/null 2>&1 || true
elif [ "$PKGMGR" = "opkg" ]; then
    opkg install --force-reinstall "$PKG_FILE" 2>&1 || \
        opkg install "$PKG_FILE" 2>&1 || true
fi

# Make sure the plugin is in place even if the package manager complained
if [ ! -f "$PLUGIN_DIR/plugin.py" ]; then
    warn "package manager did not place the files, unpacking manually ..."
    if command -v tar >/dev/null 2>&1 && command -v ar >/dev/null 2>&1; then
        ( cd "$TMPDIR_" && ar x "$PKG_FILE" 2>/dev/null && \
          tar -xzf data.tar.gz 2>/dev/null && \
          cp -a usr/lib/enigma2/python/Plugins/Extensions/AutoBiss \
                /usr/lib/enigma2/python/Plugins/Extensions/ 2>/dev/null ) || true
    fi
fi

if [ -d "$PLUGIN_DIR" ]; then
    chmod 755 "$PLUGIN_DIR"/*.py 2>/dev/null || true
    ok "plugin installed in $PLUGIN_DIR"
else
    err "installation failed — plugin folder missing"
    exit 1
fi

# the plugin has to import on the interpreter of the receiver (many images
# still run Python 2.7), otherwise it never shows up in the plugin list
PYBIN=""
for p in python2 python3 python; do
    if command -v "$p" >/dev/null 2>&1; then PYBIN="$p"; break; fi
done
if [ -n "$PYBIN" ]; then
    if ! "$PYBIN" -c "import py_compile" >/dev/null 2>&1; then
        warn "py_compile missing on this image, skipping the syntax check"
    elif "$PYBIN" -m py_compile "$PLUGIN_DIR"/*.py >/tmp/autobiss_pycheck.log 2>&1; then
        ok "python check passed ($("$PYBIN" --version 2>&1))"
    else
        err "python check failed on this receiver:"
        sed 's/^/    /' /tmp/autobiss_pycheck.log
        exit 1
    fi
fi
rm -rf "$PLUGIN_DIR/__pycache__" 2>/dev/null || true
find "$PLUGIN_DIR" -name '*.pyc' -delete 2>/dev/null || true
# DreamOS loads plugin.pyo in preference to plugin.py: stale bytecode would
# keep an old (possibly broken) build running after an upgrade.
find "$PLUGIN_DIR" -name '*.pyo' -delete 2>/dev/null || true

# the plugin must be registered with the package manager, otherwise the image
# does not list it next to the other plugins
if [ "$PKGMGR" = "dpkg" ]; then
    PKG_STATE="$(dpkg-query -W -f='${Status}' enigma2-plugin-extensions-autobiss 2>/dev/null)"
    case "$PKG_STATE" in
        "install ok installed") ok "registered in dpkg (shows up in the image plugin list)" ;;
        *) warn "dpkg state: ${PKG_STATE:-not installed}" ;;
    esac
elif [ "$PKGMGR" = "opkg" ]; then
    if opkg list-installed 2>/dev/null | grep -q enigma2-plugin-extensions-autobiss; then
        ok "registered in opkg (shows up in the image plugin list)"
    else
        warn "opkg does not list the package yet"
    fi
fi

rm -f /tmp/enigma2_plugins.xml 2>/dev/null || true

# ── 4. Restart Enigma2 ───────────────────────────────────────────────────────
if [ "$ASSUME_YES" != "1" ]; then
    echo ""
    printf '  Restart Enigma2 now? [y/N] '
    read -r ANS
    case "$ANS" in
        y|Y|yes|YES) ;;
        *) echo ""; warn "skipped — restart Enigma2 manually to load the plugin"; exit 0 ;;
    esac
fi

info "restarting Enigma2 ..."
if command -v systemctl >/dev/null 2>&1 && systemctl list-units 2>/dev/null | grep -q enigma2; then
    systemctl restart enigma2 2>/dev/null || killall -9 enigma2 2>/dev/null || true
elif [ -x /etc/init.d/enigma2 ]; then
    /etc/init.d/enigma2 restart >/dev/null 2>&1 || killall -9 enigma2 2>/dev/null || true
else
    killall -9 enigma2 2>/dev/null || true
fi
sleep 12
if ps ax 2>/dev/null | grep -v grep | grep -q "/usr/bin/enigma2"; then
    ok "Enigma2 is running again"
else
    warn "Enigma2 did not come back — rolling the plugin back"
    if [ "$PKGMGR" = "dpkg" ]; then
        dpkg --remove --force-all enigma2-plugin-extensions-autobiss >/dev/null 2>&1 || true
    else
        opkg remove enigma2-plugin-extensions-autobiss >/dev/null 2>&1 || true
    fi
    rm -rf "$PLUGIN_DIR"
    killall -9 enigma2 2>/dev/null || true
    err "plugin removed again to keep the receiver bootable"
    exit 1
fi

echo ""
ok "AutoBiss E2 v${PLUGIN_VERSION} installed"
echo "  Open it from:  Settings -> Plugins / Extensions -> AutoBiss E2"
echo "  Debug log:     /tmp/autobiss_debug.log"
echo ""
exit 0
