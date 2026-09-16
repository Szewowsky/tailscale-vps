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
setup jest idempotentny: istniejącej grupy tailscale-lockdown-VM_ID używa ponownie (dopisuje brakujące
reguły, przypina, jeśli trzeba), zamiast tworzyć drugą o tej samej nazwie.
status pokazuje grupę przypiętą do VM i sieroty o tej samej nazwie; inne grupy konta tylko z nazwy.
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


def get_vm(vm_id):
    vm = call("GET", f"/api/vps/v1/virtual-machines/{vm_id}")
    if "HTTP" in vm:
        die(f"API (VM {vm_id}): {vm}")
    return vm


def all_groups():
    """Wszystkie grupy firewalla na koncie (API stronicuje, domyślnie po 15)."""
    groups, page = [], 1
    while True:
        r = call("GET", f"/api/vps/v1/firewall?page={page}")
        if "HTTP" in r:
            die(f"API (lista grup): {r}")
        data = r.get("data") or []
        groups += data
        total = (r.get("meta") or {}).get("total", 0)
        if not data or len(groups) >= total or page >= 50:
            return groups
        page += 1


def accept_rules(group):
    return {(r.get("protocol"), str(r.get("port"))) for r in group.get("rules") or [] if r.get("action") == "accept"}


def group_line(g, mark):
    rules = ", ".join(f"{p} {n}" for p, n in sorted(accept_rules(g))) or "brak reguł accept"
    synced = str(g.get("is_synced")).lower()
    return f"{g.get('id'):>9} | {g.get('name', ''):32} | is_synced {synced:5} | accept: {rules}  {mark}"


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

    name = f"tailscale-lockdown-{vm_id}"

    if mode == "status":
        vm = get_vm(vm_id)
        attached = vm.get("firewall_group_id")
        print("VM", vm_id, vm.get("hostname"), "-> firewall_group_id:", attached)
        others = []
        for g in all_groups():
            if g.get("id") == attached:
                print(group_line(g, "<- PRZYPIĘTA DO TEJ VM (to jest FIREWALL_ID)"))
            elif g.get("name") == name:
                print(group_line(g, "<- NIEPRZYPIĘTA, ta sama nazwa: sierota, usuń w hPanelu"))
            else:
                others.append(f"{g.get('id')} {g.get('name', '')}")
        if others:
            print(f"Inne grupy na koncie ({len(others)}, nie dotyczą tej VM - nie ruszaj): " + "; ".join(others))
        if attached is None:
            print("VM nie ma przypiętej grupy - firewall Hostingera nic nie filtruje.")
        return

    if mode == "setup":
        vm = get_vm(vm_id)
        attached = vm.get("firewall_group_id")
        same = [g for g in all_groups() if g.get("name") == name]
        if len(same) > 1:
            ids = ", ".join(str(g.get("id")) for g in same)
            pinned = [g for g in same if g.get("id") == attached]
            if not pinned:
                die(f"Na koncie jest {len(same)}x grupa '{name}' ({ids}) i żadna nie jest przypięta do VM {vm_id}. "
                    "Usuń zbędne w hPanelu (VPS -> Firewall) i uruchom setup ponownie.")
            print(f"UWAGA: grupa '{name}' jest na koncie {len(same)}x ({ids}). Używam przypiętej ({attached}); "
                  "pozostałe to sieroty - usuń je w hPanelu, żeby przy planie B nie pomylić przełączników.")
            same = pinned
        if same:
            fid = same[0]["id"]
            have = accept_rules(same[0])
            print(f"grupa '{name}' już istnieje (ID {fid}) - używam jej, nie tworzę drugiej")
        else:
            fw = call("POST", "/api/vps/v1/firewall", {"name": name})
            fid = fw.get("id")
            if not fid:
                die(f"nie udało się utworzyć grupy (sprawdź token i uprawnienia): {fw}")
            have = set()
            print(f"utworzona grupa '{name}' (ID {fid})")
        rules = [("UDP", "41641")]
        if web:
            rules += [("TCP", "80"), ("TCP", "443")]
        for proto, port in rules:
            if (proto, port) in have:
                print("reguła accept", proto, port, "-> już jest")
                continue
            r = call(
                "POST",
                f"/api/vps/v1/firewall/{fid}/rules",
                {"protocol": proto, "port": port, "source": "any", "source_detail": "any", "action": "accept"},
            )
            print("reguła accept", proto, port, "->", "OK" if r.get("id") or r == {} else r)
        extra = sorted(have - set(rules))
        if extra:
            print("UWAGA: grupa ma też reguły accept:", ", ".join(f"{p} {n}" for p, n in extra),
                  "- setup ich nie usuwa (hPanel -> VPS -> Firewall)")
        if attached == fid:
            print("aktywacja na VM", vm_id, "-> już przypięta")
        else:
            if attached:
                print(f"UWAGA: VM miała przypiętą inną grupę ({attached}) - aktywacja ją zastępuje "
                      "(tamta zostaje na koncie, można ją przełączyć z powrotem w hPanelu)")
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
