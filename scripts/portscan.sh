#!/bin/bash
# =============================================================================
# Skan portów serwera Z TWOJEGO KOMPUTERA - "co widzi internet"
# =============================================================================
# Użycie:  bash portscan.sh IP [port1 port2 ...]
# Domyślna lista: typowe porty SSH, WWW i paneli. Tylko TCP (UDP 41641 Tailscale
# nie da się sprawdzić prostym connectem - i ma zostać otwarte).
# NICZEGO NIE ZMIENIA. Uruchom PRZED Fazą 5 i PO niej, porównaj.
# =============================================================================

set -uo pipefail

IP="${1:-}"
if [[ -z "$IP" ]]; then
    echo "Użycie: bash portscan.sh IP [porty...]"
    exit 1
fi
shift || true

if [[ $# -gt 0 ]]; then
    PORTS=("$@")
else
    PORTS=(22 2222 80 443 3000 3100 5173 5432 5678 8000 8080 9000)
fi

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo "Skan TCP z tego komputera -> $IP  ($(date +%H:%M:%S))"
echo "----------------------------------------------"
# macOS nc: -G = timeout połączenia (bez tego -w nie działa przy -z)
NC_OPTS=(-z -w 2)
if [[ "$(uname -s)" == "Darwin" ]]; then NC_OPTS=(-z -G 2 -w 2); fi

OPEN=0
for p in "${PORTS[@]}"; do
    if nc "${NC_OPTS[@]}" "$IP" "$p" >/dev/null 2>&1; then
        echo -e "  ${RED}OPEN  ${NC} $p"
        OPEN=$((OPEN + 1))
    else
        echo -e "  ${GREEN}closed${NC} $p"
    fi
done
echo "----------------------------------------------"
if [[ $OPEN -eq 0 ]]; then
    echo -e "${GREEN}Z internetu nie widać żadnego z tych portów.${NC}"
else
    echo -e "Otwarte z internetu: ${RED}$OPEN${NC} (sprawdź, czy każdy z nich ma być publiczny)"
fi

if command -v nmap >/dev/null 2>&1; then
    echo ""
    echo "Masz nmap - pełniejszy skan 100 najpopularniejszych portów:"
    echo "  nmap -Pn --top-ports 100 $IP"
fi
echo ""
