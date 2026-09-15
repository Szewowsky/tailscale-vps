#!/usr/bin/env python3
"""
Firewall Hostingera przez API - grupa reguł "tailscale-lockdown" dla jednego VPS.

Token: zmienna środowiskowa HOSTINGER_API_TOKEN (hPanel -> API). Nie wklejaj go do czatu.
Firewall Hostingera działa PRZED serwerem (na hiperwizorze), więc Docker go nie omija.
Domyślna polityka grupy: DROP wszystkiego, co nie ma reguły accept.

Użycie:
  python3 hostinger-firewall.py list                          # maszyny (GET)
  python3 hostinger-firewall.py status --vm VM_ID             # grupy + przypięcie (GET)
  python3 hostinger-firewall.py setup  --vm VM_ID [--web]     # utwórz grupę, reguły, aktywuj, sync (POST)
  python3 hostinger-firewall.py sync   --vm VM_ID FIREWALL_ID # wymuś sync (POST)
  python3 hostinger-firewall.py off    --vm VM_ID FIREWALL_ID # deaktywuj (plan B) (POST)

Reguły w setup: accept UDP 41641 (Tailscale); z --web dodatkowo accept TCP 80 i 443.
"""
import json
import os
import sys
import urllib.error
import urllib.request

BASE = "https://developers.hostinger.com"
TOKEN = os.environ.get("HOSTINGER_API_TOKEN", "").strip()


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        BASE + path,
        data=data,
        method=method,
        headers={
            "Authorization": "Bearer " + TOKEN,
            "Content-Type": "application/json",
            "Accept": "application/json",
            # bez User-Agent Cloudflare odrzuca (błąd 1010)
            "User-Agent": "curl/8.7.1",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        return {"HTTP": e.code, "body": e.read().decode(errors="replace")[:500]}


def die(msg):
    print(msg, file=sys.stderr)
    sys.exit(1)


def main():
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(__doc__)
        sys.exit(0)
    if not TOKEN:
        die("Brak HOSTINGER_API_TOKEN w środowisku. W swoim terminalu: export HOSTINGER_API_TOKEN='...'")

    mode = args.pop(0)
    vm_id = None
    web = False
    rest = []
    while args:
        a = args.pop(0)
        if a == "--vm":
            vm_id = int(args.pop(0))
        elif a == "--web":
            web = True
        else:
            rest.append(a)

    if mode == "list":
        vms = call("GET", "/api/vps/v1/virtual-machines")
        if isinstance(vms, dict) and "HTTP" in vms:
            die(f"API: {vms}")
        print(f"{'id':>9} | {'hostname':32} | {'ipv4':16} | firewall_group_id")
        for v in vms:
            ip = ", ".join(a.get("address", "") for a in v.get("ipv4", []))
            print(f"{v.get('id'):>9} | {v.get('hostname', ''):32} | {ip:16} | {v.get('firewall_group_id')}")
        return

    if vm_id is None:
        die("Podaj --vm VM_ID (sprawdź przez: hostinger-firewall.py list)")

    if mode == "status":
        for g in call("GET", "/api/vps/v1/firewall").get("data", []):
            print(json.dumps(g, indent=1, ensure_ascii=False))
        vm = call("GET", f"/api/vps/v1/virtual-machines/{vm_id}")
        print("VM", vm_id, vm.get("hostname"), "-> firewall_group_id:", vm.get("firewall_group_id"))
        return

    if mode == "setup":
        name = f"tailscale-lockdown-{vm_id}"
        fw = call("POST", "/api/vps/v1/firewall", {"name": name})
        print("grupa:", fw)
        fid = fw.get("id")
        if not fid:
            die("nie udało się utworzyć grupy (sprawdź token i uprawnienia)")
        rules = [("UDP", "41641")]
        if web:
            rules += [("TCP", "80"), ("TCP", "443")]
        for proto, port in rules:
            r = call(
                "POST",
                f"/api/vps/v1/firewall/{fid}/rules",
                {"protocol": proto, "port": port, "source": "any", "source_detail": "any", "action": "accept"},
            )
            print("reguła accept", proto, port, "->", "OK" if r.get("id") or r == {} else r)
        print("aktywacja na VM", vm_id, "->", call("POST", f"/api/vps/v1/firewall/{fid}/activate/{vm_id}"))
        print("sync ->", call("POST", f"/api/vps/v1/firewall/{fid}/sync/{vm_id}"))
        print("FIREWALL_ID =", fid)
        print("Sprawdź teraz z komputera: bash portscan.sh IP  (port SSH ma być closed)")
        return

    if mode in ("sync", "off"):
        if not rest:
            die("Podaj FIREWALL_ID (z setup albo status)")
        fid = int(rest[0])
        if mode == "sync":
            print("sync ->", call("POST", f"/api/vps/v1/firewall/{fid}/sync/{vm_id}"))
        else:
            print("deaktywacja ->", call("POST", f"/api/vps/v1/firewall/{fid}/deactivate/{vm_id}"))
            print("Publiczne porty są znowu otwarte. Po odzyskaniu dostępu wróć do właściwych reguł.")
        return

    die(f"Nieznany tryb: {mode}. Zobacz --help")


if __name__ == "__main__":
    main()
