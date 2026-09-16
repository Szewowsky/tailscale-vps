#!/bin/bash
# =============================================================================
# Audyt serwera pod Tailscale (PRZED i PO schowaniu za tailnetem)
# =============================================================================
# Sprawdza, czy Tailscale jest zainstalowany, zalogowany, bez wygasania klucza,
# oraz co serwer wystawia publicznie. NICZEGO NIE ZMIENIA.
#
# Uruchom na serwerze:      bash check.sh
# Audyt PRZED instalacją:   bash check.sh --before
#
# UWAGA: skrypt działa NA serwerze, więc nie widzi firewalla dostawcy (np. panel
# Hostingera). Dowodem zamknięcia portu z internetu jest scripts/portscan.sh
# uruchomiony z Twojego komputera.
# =============================================================================

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "  ${GREEN}[PASS]${NC}  $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}[FAIL]${NC}  $1"; FAIL=$((FAIL + 1)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC}  $1"; WARN=$((WARN + 1)); }
info() { echo -e "  ${BLUE}[INFO]${NC}  $1"; }
header() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }

BEFORE=0
for arg in "$@"; do
    case "$arg" in
        --before) BEFORE=1 ;;
        --after)  BEFORE=0 ;;
    esac
done
if [[ "$BEFORE" -eq 0 ]] && ! command -v tailscale >/dev/null 2>&1; then
    BEFORE=1
fi

# W trybie PRZED punkty, które robi wizard, raportujemy jako WARN, nie FAIL.
softfail() {
    if [[ "$BEFORE" -eq 1 ]]; then
        warn "$1 (robi to wizard w $2)"
    else
        fail "$1"
    fi
}

SUDO=""
if [[ $EUID -eq 0 ]]; then
    HAVE_ROOT=1
elif sudo -n true 2>/dev/null; then
    SUDO="sudo"
    HAVE_ROOT=1
else
    HAVE_ROOT=0
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║       AUDYT SERWERA POD TAILSCALE        ║"
echo "║       $(date +%Y-%m-%d\ %H:%M)                    ║"
echo "╚══════════════════════════════════════════╝"
if [[ "$BEFORE" -eq 1 ]]; then
    echo -e "${YELLOW}Tryb: audyt PRZED${NC} - Tailscale jeszcze nie ma, to jest oczekiwane."
fi

# --- 1. System ---
header "1. System"

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    case "${ID:-}-${VERSION_ID:-}" in
        ubuntu-24.04|ubuntu-22.04) pass "System: $PRETTY_NAME" ;;
        ubuntu-*) warn "System: $PRETTY_NAME (testowane na 22.04 / 24.04)" ;;
        *) warn "System: ${PRETTY_NAME:-nieznany} (install.sh Tailscale obsługuje większość dystrybucji)" ;;
    esac
else
    warn "Nie rozpoznano systemu (brak /etc/os-release)"
fi

if [[ $EUID -eq 0 ]]; then
    pass "Uruchomiono jako root"
elif [[ $HAVE_ROOT -eq 1 ]]; then
    pass "Użytkownik $(id -un) ma sudo bez hasła"
else
    warn "Brak sudo bez hasła - punkty wymagające uprawnień pominięte"
fi

PUB_IP=$(curl -4 -fsS --max-time 5 https://ifconfig.me 2>/dev/null || true)
if [[ -n "$PUB_IP" ]]; then
    info "Publiczny adres IPv4 serwera: $PUB_IP"
else
    warn "Nie udało się ustalić publicznego IP (brak wyjścia do internetu?)"
fi

# --- 2. Tailscale ---
header "2. Tailscale"

TS_IP=""
if command -v tailscale >/dev/null 2>&1; then
    pass "Tailscale zainstalowany: $(tailscale version 2>/dev/null | head -1)"

    if systemctl is-active --quiet tailscaled 2>/dev/null; then
        pass "Usługa tailscaled działa"
    else
        fail "Usługa tailscaled nie działa (sudo systemctl enable --now tailscaled)"
    fi

    STATUS_JSON=$(tailscale status --json 2>/dev/null || echo '{}')
    BACKEND=$(echo "$STATUS_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("BackendState",""))' 2>/dev/null || echo "")
    case "$BACKEND" in
        Running)
            TS_IP=$(tailscale ip -4 2>/dev/null | head -1)
            TS_NAME=$(echo "$STATUS_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"].get("HostName",""))' 2>/dev/null || echo "")
            pass "Zalogowany do tailnetu jako '$TS_NAME', adres $TS_IP"
            ;;
        NeedsLogin|"")
            softfail "Nie zalogowany do tailnetu (BackendState: ${BACKEND:-brak})" "Fazie 2"
            ;;
        *)
            warn "Stan tailscaled: $BACKEND (oczekiwane: Running)"
            ;;
    esac

    if [[ "$BACKEND" == "Running" ]]; then
        KEYEXP=$(echo "$STATUS_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"].get("KeyExpiry") or "")' 2>/dev/null || echo "")
        if [[ -z "$KEYEXP" ]]; then
            pass "Key expiry wyłączone (klucz serwera nie wygaśnie)"
        else
            softfail "Key expiry WŁĄCZONE - klucz wygasa $KEYEXP; wyłącz w konsoli: Machines -> ... -> Disable key expiry" "Fazie 4a"
        fi

        if tailscale debug prefs 2>/dev/null | grep -q '"RunSSH": true'; then
            info "Tailscale SSH włączone (logowanie bez kluczy po adresie 100.x, port 22)"
        else
            info "Tailscale SSH wyłączone (opcjonalne: sudo tailscale set --ssh)"
        fi

        ONLINE_PEERS=$(echo "$STATUS_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(sum(1 for p in d.get("Peer",{}).values() if p.get("Online")))' 2>/dev/null || echo "?")
        info "Inne urządzenia online w tailnecie: $ONLINE_PEERS"
    fi
else
    softfail "Tailscale nie zainstalowany" "Fazie 2"
fi

# --- 3. Co serwer wystawia publicznie ---
header "3. Porty nasłuchujące na wszystkich adresach (0.0.0.0 / [::])"

LISTEN=$(ss -tlnH 2>/dev/null | awk '{print $4}' | grep -E '^(0\.0\.0\.0|\*|\[::\]):' | sed -E 's/.*:([0-9]+)$/\1/' | sort -un | tr '\n' ' ')
if [[ -n "$LISTEN" ]]; then
    info "TCP publicznie: $LISTEN"
    for p in $LISTEN; do
        case "$p" in
            80|443) info "  $p - WWW / webhooki (zostaje publiczne, jeśli tego chcesz)" ;;
            22|2222) info "  $p - SSH (po Fazie 5 firewall ma go zamknąć z zewnątrz)" ;;
            *) warn "  $p - usługa wewnętrzna? Rozważ bind na adres Tailscale ${TS_IP:-100.x.y.z} zamiast 0.0.0.0" ;;
        esac
    done
else
    info "Brak usług TCP na 0.0.0.0"
fi

# -p (nazwa procesu) dla gniazd roota widać tylko z uprawnieniami - stąd $SUDO
SSHD_PORTS=$($SUDO ss -tlnpH 2>/dev/null | grep -E 'sshd' | awk '{print $4}' | sed -E 's/.*:([0-9]+)$/\1/' | sort -un | tr '\n' ' ')
if [[ -n "$SSHD_PORTS" ]]; then
    pass "sshd nasłuchuje na porcie: $SSHD_PORTS (zostaje - wejście przez tailnet idzie tym samym sshd)"
elif [[ $HAVE_ROOT -eq 0 ]]; then
    warn "Nie mogę sprawdzić sshd bez uprawnień"
else
    fail "sshd nie nasłuchuje - to jedyne wejście oprócz Tailscale SSH, sprawdź natychmiast"
fi

# --- 4. Firewall na serwerze i Docker ---
header "4. Firewall na serwerze i Docker"

if command -v ufw >/dev/null 2>&1 && [[ $HAVE_ROOT -eq 1 ]]; then
    UFW_STATUS=$($SUDO ufw status verbose 2>/dev/null || true)
    if echo "$UFW_STATUS" | grep -q "Status: active"; then
        if echo "$UFW_STATUS" | grep -q "deny (incoming)"; then
            pass "ufw aktywny, domyślnie deny incoming"
        else
            warn "ufw aktywny, ale domyślna polityka nie jest deny incoming"
        fi
        if echo "$UFW_STATUS" | grep -qE "tailscale0|41641/udp"; then
            pass "ufw przepuszcza Tailscale (tailscale0 / 41641/udp)"
        else
            warn "ufw nie ma reguły dla tailscale0 ani 41641/udp - Tailscale może działać tylko przez przekaźnik"
        fi
        for p in $SSHD_PORTS; do
            if echo "$UFW_STATUS" | grep -qE "^$p(/tcp)?\s+ALLOW IN\s+Anywhere"; then
                # Serwer nie widzi firewalla dostawcy - przy Hostingerze ta reguła zostaje celowo:
                # dzięki niej wyłączenie firewalla w panelu (plan B) przywraca dostęp.
                if [[ "$BEFORE" -eq 1 ]]; then
                    info "ufw: port SSH $p otwarty publicznie (Faza 5 zamknie go firewallem dostawcy albo ufw)"
                else
                    warn "ufw przepuszcza port SSH $p z internetu - OK tylko, jeśli zamyka go firewall dostawcy (potwierdź: bash portscan.sh ${PUB_IP:-IP}); bez firewalla dostawcy zrób Fazę 5c"
                fi
            fi
        done
    else
        info "ufw nieaktywny - jeśli używasz firewalla dostawcy (panel Hostingera), to jest OK; potwierdź skanem portscan.sh"
    fi
else
    info "ufw brak lub bez uprawnień - firewall dostawcy (panel) sprawdzasz skanem portscan.sh z komputera"
fi

if command -v docker >/dev/null 2>&1; then
    PUBLISHED=$($SUDO docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -E '0\.0\.0\.0:|:::' || true)
    if [[ -n "$PUBLISHED" ]]; then
        warn "Docker publikuje porty na 0.0.0.0 (Docker OMIJA ufw - firewall dostawcy je złapie, ufw nie):"
        echo "$PUBLISHED" | sed 's/^/          /'
    else
        pass "Docker: brak kontenerów z portami na 0.0.0.0"
    fi
else
    info "Docker nie zainstalowany"
fi

# --- Podsumowanie ---
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║              PODSUMOWANIE                ║"
echo "╠══════════════════════════════════════════╣"
echo -e "║  ${GREEN}PASS: $PASS${NC}  ${RED}FAIL: $FAIL${NC}  ${YELLOW}WARN: $WARN${NC}          ║"
echo "╚══════════════════════════════════════════╝"

if [[ "$BEFORE" -eq 1 && $FAIL -eq 0 ]]; then
    echo -e "\n${GREEN}Serwer gotowy pod Tailscale${NC} - brakuje tylko samego Tailscale, robi to Faza 2.\n"
elif [[ $FAIL -eq 0 ]]; then
    echo -e "\n${GREEN}Wygląda dobrze!${NC} Zamknięcie portu z internetu potwierdź skanem: bash portscan.sh ${PUB_IP:-IP}\n"
elif [[ $FAIL -le 2 ]]; then
    echo -e "\n${YELLOW}Kilka rzeczy do poprawienia - sprawdź punkty na czerwono.${NC}\n"
else
    echo -e "\n${RED}Serwer jeszcze nie jest gotowy - zacznij od punktów na czerwono.${NC}\n"
fi
