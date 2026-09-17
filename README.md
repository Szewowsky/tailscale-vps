# Zamykam serwer VPS na świat (i dalej mam do niego dostęp) 🔒

Schowaj SSH i panele swojego serwera przed internetem, a dostęp zostaw tylko sobie: z laptopa, z telefonu, zewsząd. Prywatna sieć Tailscale + firewall dostawcy. Gotowy wizard dla Claude Code + przewodnik krok po kroku po polsku.

## Dla kogo?

Masz VPS z Ubuntu (np. Hostinger, Hetzner, DigitalOcean), a na nim coś, co działa: bota, n8n, stronę, webhooki. Wchodzisz przez SSH na porcie 22 (albo "sprytnie" na 2222) i myślisz, że to bezpieczne. Skan portów znajduje to wejście w kilka sekund, a boty z całego świata próbują się logować od pierwszej godziny.

Po tym poradniku:

- port SSH **nie istnieje** dla internetu,
- Ty wchodzisz normalnie: `ssh vps` z Maca, z telefonu na LTE, z kawiarni,
- publiczne usługi (WWW, webhooki) **dalej działają** na 80/443,
- zgubiony laptop = unieważniasz jedno urządzenie w panelu, bez wymiany kluczy na serwerach.

### Krok zero: serwer już zabezpieczony?

Ten poradnik **nie robi hardeningu** (użytkownik nie-root, klucze SSH, fail2ban). Jeśli Twój serwer jest świeży, zacznij tutaj i wróć:

**https://szewowsky.github.io/vps-security/**

Da się przejść ten wizard także na świeżym serwerze z rootem (tak robię w filmie na testowej maszynie), ale na produkcji najpierw vps-security.

## Co dostajesz?

- **Wizard dla Claude Code** - 7 faz (F0-F6), każda z komendą, oczekiwanym wynikiem, testem zaliczenia i planem B
- **Skrypt audytu** - `scripts/check.sh` sprawdza serwer PRZED i PO: Tailscale, tailnet, key expiry, porty nasłuchujące, jądro i oczekujący restart po aktualizacji
- **Skan portów z Twojego komputera** - `scripts/portscan.sh` pokazuje, co widzi internet PRZED i PO
- **Firewall Hostingera przez API** - `scripts/hostinger-firewall.py` tworzy grupę reguł i przypina ją do VPS (dla innych dostawców: ufw, z ostrzeżeniem o Dockerze)
- **Instrukcja tekstowa** - `INSTRUKCJA.md` dla tych, którzy wolą kopiować komendy ręcznie

## Wymagania

| Co | Minimum |
|----|---------|
| Serwer | Ubuntu 22.04 / 24.04, dostęp SSH kluczem |
| Konto Tailscale | darmowe (plan Personal: 3 użytkowników, 100 urządzeń) - logowanie Google/GitHub/Microsoft/Apple |
| Twój komputer | Tailscale zainstalowany i zalogowany tym samym kontem (Mac: App Store, Windows/Linux: tailscale.com/download) |
| Telefon (opcjonalnie) | aplikacja Tailscale z tym samym kontem, do testu "z LTE" |
| Firewall | Hostinger: token API (hPanel → API); inny dostawca: `ufw` na serwerze |

## Quick Start

### Opcja A: Wklej jeden prompt agentowi (zalecane - tak robię to w filmie)

Otwórz Claude Code w nowym, pustym folderze i wklej to w całości:

```text
Sklonuj repozytorium https://github.com/Szewowsky/tailscale-vps.git do bieżącego katalogu,
przeczytaj plik .claude/commands/tailscale-setup.md i przeprowadź mnie przez opisany tam wizard
schowania mojego serwera VPS za prywatną siecią Tailscale - dokładnie według jego zasad
bezpieczeństwa i kolejności faz od F0 do F6. Idź krok po kroku: czekaj na wynik każdej komendy
i nie przechodź dalej, jeśli test fazy nie przeszedł. Zacznij od zebrania danych (Faza 0),
potem audyt PRZED przez scripts/check.sh --before i skan portów z mojego komputera przez
scripts/portscan.sh, instalacja Tailscale, test dostępu przez tailnet z DWÓCH urządzeń,
dopiero potem zamknięcie publicznego SSH w firewallu - i na końcu audyt PO oraz zestawienie:
co było na czerwono, a co jest teraz na zielono. Złota zasada: nie zamykaj starego wejścia,
dopóki nie udowodnisz, że nowe działa. Komendy z sudo buduj heredokiem zapisywanym do pliku
i uruchamianym przez ssh, nie wpisuj sudo w komendzie inline. Linki autoryzacji Tailscale
i kliknięcia w panelu wykonuję sam - Ty mi mówisz, gdzie kliknąć.
```

Agent zapyta Cię o dane serwera i dostawcę, a potem poprowadzi przez całość.
Dokładna instrukcja krok po kroku (ze zrzutami i testami "czy zadziałało"): **[poradnik](https://szewowsky.github.io/tailscale-vps/)**.

Masz **Codex** zamiast Claude Code? Ten sam prompt działa - Codex czyta `AGENTS.md` z repo,
który wskazuje na ten sam wizard. Nie używaj `/tailscale-setup` (to komenda Claude Code), po prostu
wklej prompt.

### Opcja B: Z Claude Code, ręcznie przez slash command

```bash
git clone https://github.com/Szewowsky/tailscale-vps.git
cd tailscale-vps
claude
# wpisz: /tailscale-setup
```

### Opcja C: Ręcznie, bez agenta

Wszystkie komendy w tej samej kolejności znajdziesz w **[INSTRUKCJA.md](INSTRUKCJA.md)**.
Audyt serwera przed startem:

```bash
scp ./scripts/check.sh twoj_user@TWOJE_IP:/tmp/
ssh twoj_user@TWOJE_IP "bash /tmp/check.sh --before"
```

## 7 faz wizarda

| # | Faza | Test zaliczenia |
|---|------|-----------------|
| F0 | Dane: adres, użytkownik, port SSH, dostawca, drugie urządzenie | wszystkie pola zebrane, nic nie zgadywane |
| F1 | Audyt PRZED + skan portów z Twojego komputera + aktualizacja systemu | `check.sh --before` bez FAIL w wymaganiach; skan pokazuje port SSH otwarty (to jest "przed"); `apt-get upgrade` przeszedł, a `/var/run/reboot-required` jest obsłużony (restart za zgodą) |
| F2 | Tailscale na serwerze + `tailscale up` | serwer widoczny w `tailscale status` na Twoim komputerze |
| F3 | Test nowego mostu: SSH przez tailnet z komputera I z telefonu | dwa udane logowania po adresie `100.x.y.z`; `tailscale ping` mówi `direct` albo `relay` |
| F4 | Key expiry OFF (+ opcjonalnie Tailscale SSH bez kluczy) | `check.sh` pokazuje "key expiry wyłączone" |
| F5 | Zamknięcie publicznego SSH: firewall Hostingera (API) albo ufw | skan z komputera: port SSH zamknięty; SSH przez tailnet dalej działa |
| F6 | Audyt PO + zestawienie przed/po | zero FAIL, port SSH niewidoczny z internetu |

## Audyt

Nie wiesz, w jakim stanie jest serwer? Uruchom audyt (na serwerze) i skan (z komputera):

```bash
bash check.sh --before    # przed: brak Tailscale to WARN, nie FAIL
bash check.sh             # po: wszystko ma być zielone
bash portscan.sh TWOJE_IP # z Twojego komputera: co widzi internet
```

Dostaniesz raport PASS/WARN/FAIL: system, Tailscale (zainstalowany, zalogowany, key expiry, Tailscale SSH), porty nasłuchujące na publicznym adresie, firewall. Skrypt **niczego nie zmienia** - można go puszczać ile razy chcesz.

## Ważne

- **Najpierw nowy most, potem rozbiórka starego.** Publiczny port SSH zamykasz dopiero po dwóch udanych logowaniach przez tailnet (komputer + telefon). Wizard nie pozwoli inaczej
- **Docker omija ufw.** Kontener z `-p 8080:8080` jest widoczny z internetu mimo `ufw deny`. Dlatego na Hostingerze używamy firewalla w panelu (działa przed serwerem), a przy ufw bindujemy usługi wewnętrzne na adres Tailscale zamiast `0.0.0.0`
- **Wyłącz key expiry dla serwera.** Domyślnie klucz urządzenia wygasa po 180 dniach; serwer bez tego wypada z sieci w środku nocy i zostajesz bez wejścia
- **Plan B zanim zamkniesz:** Hostinger - firewall wyłączasz z panelu (także z telefonu); inni dostawcy - konsola VNC/serial w panelu. Sprawdź, gdzie to jest, ZANIM zamkniesz 22
- **Konsola web Hostingera nie wejdzie na serwer z zablokowanym logowaniem root** - nie traktuj jej jako jedynego planu B
- **UDP 41641 zostaje otwarte** - to port, przez który Tailscale zestawia bezpośredni tunel. Bez niego ruch pójdzie przez przekaźnik (wolniej, ale działa)
- **Tailscale "widzi" tylko metadane** (klucze publiczne, adresy, nazwy urządzeń). Ruch idzie bezpośrednio między Twoimi urządzeniami, zaszyfrowany WireGuardem. Serwer koordynacyjny kojarzy pary, nie podsłuchuje
- Testuj na świeżym VPS, zanim ruszysz produkcję

## Czym jest Tailscale

[Tailscale](https://tailscale.com) to usługa budująca prywatną sieć (tailnet) z Twoich urządzeń na bazie open-source'owego protokołu WireGuard. Klient jest open source ([github.com/tailscale/tailscale](https://github.com/tailscale/tailscale), BSD-3), serwer koordynacyjny jest usługą firmy Tailscale Inc. (jest też jego open-source'owy zamiennik [Headscale](https://github.com/juanfont/headscale)). To repo **nie jest** częścią projektu Tailscale ani nie jest przez niego firmowane - to nieoficjalny poradnik po polsku.

## Licencja

MIT - patrz [LICENSE](LICENSE).

---

Materiał towarzyszący do filmu na YouTube. Kanał: [Robert Szewczyk](https://youtube.com/@robert_szewczyk)
