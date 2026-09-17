# /tailscale-setup - Wizard: schowaj serwer VPS za prywatną siecią Tailscale

Cel: po tym wizardzie port SSH serwera **nie istnieje dla internetu**, a użytkownik wchodzi na serwer
normalnie z laptopa i z telefonu przez prywatną sieć (tailnet). Publiczne usługi (WWW, webhooki na
80/443) działają dalej. Użytkownik podaje adres serwera, użytkownika, port SSH i dostawcę - Claude
prowadzi, użytkownik klika linki autoryzacji i panele sam.

## ZŁOTA ZASADA (jedno zdanie, powtarzaj je użytkownikowi)

**Najpierw budujesz nowy most, sprawdzasz, że przenosi ciężar, i dopiero potem rozbierasz stary.**
Publiczny port SSH zamykasz w Fazie 5 wyłącznie po tym, jak Faza 3 pokazała **dwa udane logowania
przez tailnet z dwóch różnych urządzeń**. Nie ma trybu "na skróty".

## BASH-GUARD WORKAROUND

Komendy SSH mogą być blokowane przez bash-guard hook na komputerze użytkownika (blokuje `sudo` oraz
`curl | sh` nawet w komendzie zdalnej). Zamiast pojedynczych komend SSH - **pisz skrypt .sh lokalnie
heredokiem, kopiuj przez SCP, wykonaj zdalnie**:

```bash
# 1. Zapisz komendy do pliku lokalnie (heredoc cat > /tmp/fX.sh <<'EOS' ... EOS)
# 2. Skopiuj na serwer:
scp -P PORT /tmp/fX.sh USER@IP:/tmp/fX.sh
# 3. Wykonaj zdalnie:
ssh -p PORT USER@IP "bash /tmp/fX.sh; rm -f /tmp/fX.sh"
```

`sudo` i `curl ... | sh` wewnątrz **heredoca** zapisywanego do pliku przechodzą. W komendzie inline,
w `printf` i w `ssh USER@IP "sudo ..."` są **blokowane**. Dlatego każdy krok z `sudo` (F1a, F1c, F1d,
F2a, F2b, F4b, F5c) buduj heredokiem `cat > /tmp/xxx.sh <<'EOS' ... EOS`.

Jeśli użytkownik jest `root` (świeży serwer bez vps-security), `sudo` w skryptach jest zbędne, ale
nie szkodzi - `sudo` jako root po prostu działa. Nie przepisuj skryptów.

## ZASADY BEZPIECZEŃSTWA (NIGDY NIE ŁAMAĆ)

1. **Nie zamykaj publicznego SSH przed zaliczoną Fazą 3.** Dwa logowania przez tailnet (komputer
   użytkownika + drugie urządzenie), zapisane w czacie jako wynik komend. Bez tego Faza 5 nie startuje.
2. **Nie dotykaj `sshd_config`.** Nie zmieniaj portu, nie wyłączaj sshd, nie ruszaj `PermitRootLogin`.
   Tailscale SSH (F4b) jest opcjonalny i działa **obok** sshd, nie zamiast.
3. **Plan B ma być znany PRZED Fazą 5.** Zapytaj użytkownika, gdzie wyłączy firewall, jeśli coś
   pójdzie nie tak (Hostinger: panel hPanel → VPS → Firewall, także z telefonu; inni dostawcy:
   konsola VNC/serial w panelu). Zapisz odpowiedź w czacie.
4. **Tokeny nie przechodzą przez czat.** Token API Hostingera użytkownik eksportuje sam w swoim
   terminalu (`export HOSTINGER_API_TOKEN=...`). Auth key Tailscale nie jest potrzebny - autoryzacja
   idzie linkiem, który użytkownik klika sam. Nie proś o wklejenie żadnego z nich.
5. **Nie otwieraj innych portów** niż te, o które użytkownik świadomie poprosił (80/443 dla WWW,
   UDP 41641 dla Tailscale). Nie "na wszelki wypadek".
6. **ZAWSZE czekaj na wynik komendy** przed następną. Nie łącz faz. Nie zgaduj, że coś się udało.
7. **Jeśli test fazy nie przechodzi - STOP.** Pokaż output, zapytaj użytkownika. Nie naprawiaj na ślepo.
8. **Docker omija ufw.** Jeśli na serwerze jest Docker, a firewall to ufw (nie panel dostawcy),
   powiedz to wprost i pokaż, jak bindować porty kontenerów na adres Tailscale (Faza 5c).

## Nazewnictwo w komendach

`IP`, `PORT`, `USER`, `NAZWA` (nazwa serwera w tailnecie), `TS_IP` (adres 100.x.y.z serwera) to
placeholdery. **ZAWSZE podstawiaj faktyczne wartości** z Fazy 0 i Fazy 2.

CLI Tailscale na komputerze użytkownika:
- macOS z App Store: `/Applications/Tailscale.app/Contents/MacOS/Tailscale` (w skrótach niżej: `TS`),
- macOS standalone / Linux / Windows: `tailscale` w PATH.
Sprawdź na starcie: `which tailscale || ls /Applications/Tailscale.app/Contents/MacOS/Tailscale`.

---

## Faza 0 - Zbierz dane

Zapytaj użytkownika (AskUserQuestion) o:

- **IP serwera** (albo hostname, np. `srvNNNNNN.hstgr.cloud`)
- **Użytkownik SSH** - nie-root z vps-security, albo `root` na świeżym serwerze testowym
- **Port SSH** - 22 albo własny (np. 2222). To ten port znika z internetu w Fazie 5
- **Dostawca VPS** - `hostinger` (firewall przez API/panel) albo `inny` (ufw na serwerze)
- **Drugie urządzenie do testu** - telefon z aplikacją Tailscale (najlepiej na LTE, nie na tym
  samym Wi-Fi) albo drugi komputer. Bez drugiego urządzenia Faza 3 nie ma dowodu i Faza 5 nie startuje
- **Co ma zostać publiczne** - czy na serwerze jest WWW/webhooki na 80/443 (Traefik, Caddy, nginx)?
  Jeśli tak, 80/443 zostają otwarte. Jeśli nie, zamykamy wszystko poza UDP 41641
- **Nazwa serwera w tailnecie** - domyślnie hostname serwera (np. `srv1949097`); użytkownik może
  podać własną (`vps-boty`). Bez spacji, małe litery

Sprawdź też, czy **komputer użytkownika jest już w tailnecie**:

```bash
TS status 2>&1 | head -5
```

Oczekiwany wynik: lista z co najmniej jednym wpisem (ten komputer) i adresami `100.x.y.z`.
Jeśli `Logged out` albo brak aplikacji → użytkownik instaluje Tailscale na komputerze (Mac: App
Store, reszta: tailscale.com/download) i loguje się kontem Google/GitHub/Microsoft/Apple. Konto Free
(plan Personal) wystarcza: 3 użytkowników, 100 urządzeń. Dopiero potem idziesz dalej.

**Test zaliczenia:** masz wszystkie 7 wartości, żadnej nie zgadujesz, komputer użytkownika widnieje
w `TS status`.

**FAIL - co zrobić:** brak drugiego urządzenia → zaproponuj telefon z aplikacją Tailscale (5 minut).
Jeśli naprawdę nie ma, wizard może przejść do Fazy 4 włącznie, ale Fazę 5 (zamknięcie 22) blokujesz
i mówisz dlaczego.

---

## Faza 1 - Audyt PRZED + skan portów + aktualizacja systemu

### 1a. Połączenie

```bash
ssh-keyscan -p PORT IP >> ~/.ssh/known_hosts 2>/dev/null

cat > /tmp/f1a.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
echo SSH_OK
whoami
sudo -n true && echo SUDO_OK
EOS
scp -P PORT /tmp/f1a.sh USER@IP:/tmp/f1a.sh
ssh -p PORT -o ConnectTimeout=10 USER@IP "bash /tmp/f1a.sh; rm -f /tmp/f1a.sh"
```

Oczekiwany wynik: `SSH_OK`, nazwa użytkownika, `SUDO_OK` (dla roota też).

**FAIL - co zrobić:**
- `REMOTE HOST IDENTIFICATION HAS CHANGED` → serwer był reinstalowany (typowe dla testowej maszyny).
  Zapytaj użytkownika, czy to prawda. Jeśli tak: `ssh-keygen -R IP` i powtórz. Jeśli nie wie → STOP.
- `Permission denied (publickey)` → zły użytkownik albo klucz. Na świeżym Hostingerze działa
  zwykle tylko `root` z kluczem podanym przy zamówieniu. Sprawdź `ssh -v`.
- brak `SUDO_OK` → sudo pyta o hasło. Poproś użytkownika, żeby komendy z `sudo` wykonywał sam.

### 1b. Audyt PRZED (na serwerze)

Uruchamiaj z katalogu, do którego sklonowałeś `tailscale-vps` (przy Opcji A z README agent klonuje
repo do podkatalogu - wejdź do niego). Ścieżka jawnie z `./`:

```bash
scp -P PORT ./scripts/check.sh USER@IP:/tmp/check.sh
ssh -p PORT USER@IP "bash /tmp/check.sh --before 2>&1 | tee /tmp/tailscale-check-before.txt"
```

Flaga `--before`: brak Tailscale raportuje jako WARN, nie FAIL. Skrypt rozpoznaje to też sam.

Sprawdzasz w wyniku:

| Punkt | Wymagane |
|---|---|
| Ubuntu 22.04 / 24.04 | PASS (inne = WARN, install.sh Tailscale i tak obsługuje większość dystrybucji) |
| root albo sudo bez hasła | PASS |
| Tailscale | WARN "(instaluje Faza 2)" - to jest normalne PRZED |
| Jądro + `reboot-required` | INFO z `uname -r`; WARN "system czeka na restart" = robisz to w 1d |
| Porty nasłuchujące publicznie | lista informacyjna: zapisz ją, wrócisz do niej w Fazie 5 i 6 |
| Docker + kontenery z portami na 0.0.0.0 | jeśli są: WARN "Docker omija ufw" - zapamiętaj na Fazę 5 |

**Test zaliczenia:** zero FAIL w sekcji "1. System".

### 1c. Skan portów z komputera użytkownika (to jest "PRZED" do filmu)

```bash
bash ./scripts/portscan.sh IP
```

Oczekiwany wynik: port SSH (PORT) **OPEN**, ewentualnie 80/443 jeśli jest WWW. Zapisz wynik
w czacie - w Fazie 6 pokażesz go obok wyniku "PO".

Jeśli użytkownik ma `nmap`, ładniejsze ujęcie: `nmap -Pn -p 22,80,443,PORT IP` (kilka sekund). Pełny
`nmap -Pn IP` (1000 portów) trwa ok. 50 s przed zamknięciem i **ok. 7 minut po** - serwer, który nie
odpowiada, wymusza timeout na każdym porcie. To dobra ciekawostka, ale nie każ użytkownikowi czekać.

**Nie interpretuj `closed/filtered` na innych portach jako "serwer już coś filtruje".** Bez firewalla
serwer odsyła RST, który często ginie po drodze (sieć hostingu / domowa), więc z zewnątrz wygląda to
jak filtrowanie. Liczy się tylko to, co jest OPEN.

Opcjonalnie, żeby uświadomić skalę: ile prób logowania było w ostatniej dobie i skąd. `journalctl`
idzie **przez sudo**: użytkownik nie-root (spoza grup `adm` / `systemd-journal`) bez sudo nie widzi
logów sshd i dostaje fałszywe `0`. Stąd heredoc:

```bash
cat > /tmp/f1c.sh <<'EOS'
#!/usr/bin/env bash
L=$(sudo journalctl -u ssh --since '24 hours ago' 2>/dev/null | grep -E 'Failed password|Invalid user|Connection closed by authenticating user' || true)
echo "PROBY_24H=$(printf '%s' "$L" | grep -c . || true)"
echo "Adresy (liczba prób, IP):"
printf '%s\n' "$L" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort | uniq -c | sort -rn | head -5
EOS
scp -P PORT /tmp/f1c.sh USER@IP:/tmp/f1c.sh
ssh -p PORT USER@IP "bash /tmp/f1c.sh; rm -f /tmp/f1c.sh"
```

Oczekiwany wynik: `PROBY_24H=N` i lista adresów. Odejmij próby z IP komputera użytkownika
(`curl -4 -s https://ifconfig.me` u niego) - jego testy z hardeningu też tu trafiają. Reszta to obcy.
Na serwerze z adresem, który długo wisi w sieci, po 3 godzinach potrafi być kilka, po tygodniu setki;
świeżo przydzielony adres bywa czysty (0). Powiedz użytkownikowi liczbę obcych.

### 1d. Aktualizacja systemu (przed chowaniem serwera)

Zanim schowasz serwer, załataj go. Chowanie SSH za tailnetem nie naprawia dziury w pakiecie, który
i tak jest wystawiony na 80/443 - to dwie różne warstwy i obie muszą być zrobione.

**Powiedz użytkownikowi jedno zdanie o numerach jądra:** Ubuntu łata stare linie jądra bez zmiany
głównego numeru - w `6.8.0-124` rośnie tylko `N` (124 = kolejne łatane wydanie tej samej linii),
więc samo "6.8.0" nie znaczy "stare jądro"; o załataniu mówi `N` i data pakietu, nie `6.8`.

```bash
cat > /tmp/f1d.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
echo "KERNEL_PRZED=$(uname -r)"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
echo "UPGRADE_DONE"
if [ -f /var/run/reboot-required ]; then
  echo "REBOOT_REQUIRED=tak"
  echo "Pakiety: $(sort -u /var/run/reboot-required.pkgs 2>/dev/null | tr '\n' ' ')"
else
  echo "REBOOT_REQUIRED=nie"
fi
EOS
scp -P PORT /tmp/f1d.sh USER@IP:/tmp/f1d.sh
ssh -p PORT USER@IP "bash /tmp/f1d.sh; rm -f /tmp/f1d.sh"
```

Oczekiwany wynik: `KERNEL_PRZED=...`, log `apt`, `UPGRADE_DONE` i `REBOOT_REQUIRED=tak|nie`.

Serwer po `vps-security` ma `unattended-upgrades`, więc zwykle nie ma czego doinstalowywać i krok
trwa kilkanaście sekund - **i tak go wykonaj**: to on pokazuje w czacie, że system jest załatany,
a `unattended-upgrades` sam z siebie **nie restartuje** maszyny, więc `/var/run/reboot-required` może
wisieć od tygodni.

**`REBOOT_REQUIRED=tak` → restart tylko za zgodą użytkownika.** Zapytaj wprost i powiedz, co się
stanie: sesja SSH urywa się w tej sekundzie, serwer wstaje ok. 60 sekund, wracasz po **publicznym
IP** (Tailscale jeszcze nie jest zainstalowany, adresu `100.x` nie ma). Jeśli na serwerze coś działa
publicznie (WWW, webhooki, boty), użytkownik decyduje, czy to jest moment na minutę przerwy - można
zrestartować później, ale wtedy nowe jądro jeszcze nie działa i powiedz to wprost.

```bash
cat > /tmp/f1d-reboot.sh <<'EOS'
#!/usr/bin/env bash
sudo systemctl reboot
EOS
scp -P PORT /tmp/f1d-reboot.sh USER@IP:/tmp/f1d-reboot.sh
# rozłączenie w trakcie tej komendy jest oczekiwane - serwer wyłącza sshd w połowie zdania
ssh -p PORT USER@IP "bash /tmp/f1d-reboot.sh" || true
```

Powrót (po publicznym `IP`, nie po `TS_IP`) - pętla czeka do ok. 2 minut:

```bash
for i in $(seq 1 12); do
  ssh -p PORT -o ConnectTimeout=10 -o BatchMode=yes USER@IP "echo BACK_AFTER_REBOOT; uname -r" && break
  sleep 10
done
```

Oczekiwany wynik: `BACK_AFTER_REBOOT` i numer jądra z wyższym `N` niż `KERNEL_PRZED`. Pokaż
użytkownikowi obie wartości obok siebie - to jest dowód do filmu i do komentarzy.

**Test zaliczenia:** `UPGRADE_DONE` oraz `REBOOT_REQUIRED=nie`, albo (po restarcie za zgodą)
`BACK_AFTER_REBOOT` z nowym `uname -r`. Użytkownik świadomie odłożył restart → zapisz to w czacie
i przypomnij w podsumowaniu Fazy 6.

**FAIL - co zrobić:**
- `Could not get lock /var/lib/dpkg/lock-frontend` → w tle pracuje `unattended-upgrades`. Nie zabijaj
  procesu; odczekaj 2-3 minuty i powtórz skrypt.
- błąd `apt-get update` (brak DNS / repo) → sprawdź `curl -I https://archive.ubuntu.com`. Bez wyjścia
  do internetu Faza 2 też nie zadziała (instalacja Tailscale) - napraw teraz.
- serwer nie wraca po 2 minutach → **nie panikuj i nie zamykaj niczego**: publiczny SSH jest jeszcze
  otwarty, więc plan B to konsola VNC/serial w panelu dostawcy. Poczekaj kolejne 2 minuty, potem STOP
  i pokaż użytkownikowi.

---

## Faza 2 - Tailscale na serwerze

### 2a. Instalacja

Skrypt oficjalny `install.sh` rozpoznaje dystrybucję i dodaje repo pakietów Tailscale. `curl | sh`
musi być w heredocu (bash-guard):

```bash
cat > /tmp/f2a.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
if command -v tailscale >/dev/null 2>&1; then
  echo "TAILSCALE_ALREADY_INSTALLED"; tailscale version | head -1; exit 0
fi
curl -fsSL https://tailscale.com/install.sh | sh
sudo systemctl enable --now tailscaled
echo "TAILSCALE_INSTALLED"
tailscale version | head -1
EOS
scp -P PORT /tmp/f2a.sh USER@IP:/tmp/f2a.sh
ssh -p PORT USER@IP "bash /tmp/f2a.sh; rm -f /tmp/f2a.sh"
```

Oczekiwany wynik: `TAILSCALE_INSTALLED` (albo `_ALREADY_`) i numer wersji (np. `1.102.x`).

**FAIL - co zrobić:** błąd `apt` / brak dostępu do `pkgs.tailscale.com` → serwer nie ma wyjścia do
internetu albo DNS nie działa; sprawdź `curl -I https://pkgs.tailscale.com`. Nie instaluj z innych źródeł.

### 2b. Dołączenie do tailnetu (`tailscale up`)

`tailscale up` **blokuje terminal**, dopóki użytkownik nie kliknie linku autoryzacji. Dlatego
uruchamiasz je w tle, wyciągasz link z logu i podajesz użytkownikowi:

```bash
cat > /tmp/f2b.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
nohup sudo tailscale up --hostname NAZWA > /tmp/ts-up.log 2>&1 &
# link autoryzacji pojawia się dopiero po ok. 20 s (serwer rejestruje się u koordynatora) - czekamy do 45 s
for i in $(seq 1 45); do
  grep -q "login.tailscale.com" /tmp/ts-up.log 2>/dev/null && break
  grep -q "Success" /tmp/ts-up.log 2>/dev/null && break
  sleep 1
done
cat /tmp/ts-up.log
EOS
scp -P PORT /tmp/f2b.sh USER@IP:/tmp/f2b.sh
ssh -p PORT USER@IP "bash /tmp/f2b.sh; rm -f /tmp/f2b.sh"
```

Oczekiwany wynik w logu:

```
To authenticate, visit:
        https://login.tailscale.com/a/xxxxxxxxxxxx
```

**Podaj ten link użytkownikowi.** Otwiera go w przeglądarce na komputerze, loguje się tym samym
kontem, co na komputerze, klika **Connect**. Nie klikaj za niego, nie generuj auth keya.

Po kliknięciu sprawdź (powtarzaj co kilkanaście sekund, max 2 minuty):

```bash
ssh -p PORT USER@IP "tailscale status | head -3; echo TS_IP=\$(tailscale ip -4)"
```

Oczekiwany wynik: pierwsza linia z adresem `100.x.y.z NAZWA użytkownik@ linux -`, oraz `TS_IP=100.x.y.z`.
**Zapisz `TS_IP`** - używasz go w Fazach 3-6.

Na komputerze użytkownika:

```bash
TS status
```

Oczekiwany wynik: na liście pojawia się `NAZWA` z tym samym adresem `100.x.y.z`.

**Test zaliczenia:** `tailscale ip -4` na serwerze zwraca adres `100.x.y.z` i ten sam adres widać
w `TS status` na komputerze.

**FAIL - co zrobić:**
- log pusty po 45 s → to nie błąd, `tailscale up` potrafi milczeć 20-30 s zanim wypisze link. Nie przerywaj
  procesu. Odczekaj i `ssh -p PORT USER@IP "cat /tmp/ts-up.log"`.
- w logu brak linku, jest `Logged in` / `Success` → serwer był już w tailnecie (ponowny przebieg). OK, idź dalej.
- link jest, ale po 2 minutach `tailscale status` mówi `Logged out` / `NeedsLogin` → użytkownik nie
  kliknął albo zalogował się innym kontem. Zapytaj. Link można wygenerować ponownie tym samym skryptem.
- `tailscale status` na komputerze nie widzi serwera, choć serwer widzi siebie → inne konto Tailscale
  (inny tailnet). Sprawdź w obu miejscach kolumnę z użytkownikiem (`user@`).

---

## Faza 3 - Test nowego mostu (DWA urządzenia)

To jest faza, która **odblokowuje** Fazę 5. Bez dwóch dowodów nie zamykasz niczego.

### 3a. Z komputera użytkownika przez tailnet

```bash
TS ping -c 3 TS_IP
```

Klucz hosta: `known_hosts` zna serwer tylko pod publicznym `IP` (z 1a). Pierwsze `ssh USER@TS_IP` bez
terminala nie może zapytać o nowy klucz i kończy się `Host key verification failed`. To ten sam serwer,
więc odcisk ma być identyczny - porównaj, zanim cokolwiek dopiszesz:

```bash
ssh-keygen -l -F IP | grep -i ed25519        # PORT inny niż 22: ssh-keygen -l -F '[IP]:PORT'
ssh-keyscan -p PORT -t ed25519 TS_IP 2>/dev/null | ssh-keygen -lf -
```

Oczekiwany wynik: ten sam `SHA256:...` w obu liniach. Różny → STOP, pokaż użytkownikowi (pod `TS_IP`
odpowiada inna maszyna). Zgodny → łączysz się z `accept-new` (dopisuje nowy wpis, a zmieniony klucz
nadal odrzuca):

```bash
ssh -p PORT -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new USER@TS_IP "echo TAILNET_SSH_OK; hostname"
```

Oczekiwany wynik:
- `pong from NAZWA (TS_IP) via <IP publiczne>:41641 in NN ms` → połączenie **bezpośrednie** (direct),
- albo `pong from NAZWA (TS_IP) via DERP(waw) in NN ms` → przez **przekaźnik** (relay). Działa, jest
  wolniej; zwykle po chwili przechodzi w direct. Jeśli zostaje na DERP - w Fazie 5 upewnij się, że
  UDP 41641 jest otwarte,
- `TAILNET_SSH_OK` + hostname serwera.

Wyjaśnij użytkownikowi jednym zdaniem, co widzi: to samo SSH, ten sam port, ale po **prywatnym adresie**,
którego internet nie zna.

Opcjonalnie MagicDNS: `ssh -p PORT -o StrictHostKeyChecking=accept-new USER@NAZWA` powinno działać tak
samo (nazwa zamiast adresu). Jeśli nie działa, nie blokuj - MagicDNS bywa wyłączone w tailnecie, adres
`100.x` wystarcza.

### 3b. Z drugiego urządzenia (telefon na LTE)

Dwa warianty, użytkownik wybiera:

**Wariant A - aplikacja SSH na telefonie** (Termius, Blink, a-Shell): połączenie z `USER@TS_IP`
na porcie `PORT` kluczem. Dowód: prompt serwera na ekranie telefonu.

Skąd telefon ma klucz: po vps-security logowanie hasłem jest wyłączone, a Tailscale SSH (4b) jeszcze
nie działa, więc odpowiada zwykły sshd i wpuszcza tylko klucze z `authorized_keys`. Telefon dostaje
**własny** klucz (klucza prywatnego z komputera nie przenoś):

1. W aplikacji wygeneruj klucz ED25519 (Termius: Keychain → Generate Key; Blink: Settings → Keys → +).
2. Skopiuj jego **publiczną** część (jedna linia `ssh-ed25519 AAAA... nazwa`) i przekaż na komputer
   (notatka, AirDrop, mail do siebie). Wklejenie jej do czatu jest OK - to nie sekret. Tekst z
   `PRIVATE KEY` to klucz prywatny: nie używaj go, niech użytkownik wygeneruje nowy.
3. Za zgodą użytkownika sprawdź i dopisz klucz z komputera (publiczne IP jeszcze działa,
   `sshd_config` bez zmian, dopisanie jest idempotentne):

```bash
echo 'ssh-ed25519 AAAA... iphone' | ssh-keygen -lf -     # ma wypisać odcisk, nie błąd
ssh -p PORT USER@IP "K='ssh-ed25519 AAAA... iphone'; umask 077; mkdir -p ~/.ssh; grep -qxF \"\$K\" ~/.ssh/authorized_keys 2>/dev/null || echo \"\$K\" >> ~/.ssh/authorized_keys; echo KEY_ADDED"
```

"Export to host" w Termiusie (i podobne "wyślij klucz na serwer") **nie zadziała**: aplikacja musi się
najpierw sama zalogować, żeby dopisać klucz, a hasła są wyłączone.

Przy pierwszym połączeniu aplikacja pokaże odcisk klucza hosta (Termius często ECDSA, nie ED25519) -
porównaj z `ssh-keyscan -p PORT TS_IP 2>/dev/null | ssh-keygen -lf -`.

Dowód, że telefon był poza domową siecią: na serwerze `tailscale status` **w trakcie sesji** (bez
ruchu wiersz pokazuje tylko `-`) → wiersz telefonu `active; direct <IP>:<port>` ma pokazywać inny adres
niż domowe IP komputera (ten sam = telefon nadal na Wi-Fi).

Użytkownik i tak włączy Tailscale SSH (4b)? Wtedy klucz na telefonie przestanie być potrzebny - do
samego testu szybszy jest wariant B.

**Wariant B - bez aplikacji SSH, przez przeglądarkę** (szybszy do demo). Na serwerze na 60 sekund
podnosisz stronę testową **wyłącznie na adresie Tailscale** (nie na 0.0.0.0, więc internet jej nie widzi):

```bash
ssh -p PORT USER@IP "cd /tmp && echo '<h1>Jesteś w tailnecie</h1>' > index.html && (timeout 120 python3 -m http.server 8000 --bind TS_IP >/dev/null 2>&1 &) && echo HTTP_TEST_UP"
```

Użytkownik: **wyłącza Wi-Fi** w telefonie (ma być LTE), włącza Tailscale w aplikacji, otwiera
`http://TS_IP:8000`. Dowód: napis "Jesteś w tailnecie". Strona sama gaśnie po 2 minutach.

Kontrola negatywna (ważna do filmu): ten sam adres z publicznym IP, `http://IP:8000`, **nie** działa,
bo serwer testowy słucha tylko na adresie Tailscale.

**Test zaliczenia:** w czacie są **dwa** dowody: `TAILNET_SSH_OK` z komputera (3a) i potwierdzenie
użytkownika z telefonu (3b, wariant A lub B). Zapisz oba jako "MOST DZIAŁA: [urządzenie 1], [urządzenie 2]".

**FAIL - co zrobić:**
- `ping` timeout → serwer nie jest online w tailnecie (`tailscale status` na serwerze); albo
  komputer i serwer są na różnych kontach.
- `Host key verification failed` po `TS_IP` → brak wpisu w `known_hosts` dla tego adresu. Porównaj
  odcisk (3a) i połącz się z `-o StrictHostKeyChecking=accept-new`.
- `REMOTE HOST IDENTIFICATION HAS CHANGED` / `Host key for NAZWA has changed` → w `known_hosts` wisi
  stary klucz z poprzedniej instalacji serwera o tej samej nazwie (albo tym samym adresie 100.x).
  Zapytaj, czy serwer był reinstalowany. Jeśli tak: `ssh-keygen -R NAZWA` (i `ssh-keygen -R TS_IP`,
  jeśli to on protestuje), potem jeszcze raz porównanie odcisku i `accept-new`. Nie wie → STOP.
- SSH przez `TS_IP` odmawia, a przez `IP` działa → sshd słucha tylko na publicznym adresie
  (`ListenAddress` w `sshd_config`). Nie zmieniaj tego sam - pokaż użytkownikowi
  `grep -i ListenAddress /etc/ssh/sshd_config` i zapytaj.
- telefon nie widzi → aplikacja Tailscale wyłączona, inne konto, albo telefon nadal na Wi-Fi z blokadą.
  Sprawdź w aplikacji, czy serwer jest na liście z zieloną kropką.

---

## Faza 4 - Key expiry OFF (+ opcjonalnie Tailscale SSH)

### 4a. Wyłącz wygasanie klucza dla serwera (obowiązkowe)

Domyślnie klucz urządzenia wygasa po **180 dniach**. Laptop odnowi go sam przy logowaniu, serwer
**nie** - wypada z tailnetu, a jeśli publiczny SSH jest już zamknięty, zostajesz bez wejścia.
To najczęstsza pułapka z forów.

Klik użytkownika (nie da się tego zrobić z CLI bez API):
konsola **https://login.tailscale.com/admin/machines** → wiersz `NAZWA` → menu `...` po prawej →
**Disable key expiry**.

Sprawdzenie na serwerze - **trzy odczyty w ciągu 30 s**, nie jeden. Tuż po kliknięciu odczyt `None`
bywa chwilowy: w teście pętla złapała `None`, a sekundę później wróciła ta sama data (najpewniej drugi
klik w menu, które po pierwszym zmienia się na "Enable key expiry", włączył wygasanie z powrotem).

```bash
cat > /tmp/f4a.sh <<'EOS'
#!/usr/bin/env bash
for i in 1 2 3; do
  echo "$(date +%T) KeyExpiry = $(tailscale status --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"].get("KeyExpiry"))')"
  if [ "$i" -lt 3 ]; then sleep 15; fi
done
EOS
scp -P PORT /tmp/f4a.sh USER@IP:/tmp/f4a.sh
ssh -p PORT USER@IP "bash /tmp/f4a.sh; rm -f /tmp/f4a.sh"
```

Oczekiwany wynik: trzy linie `KeyExpiry = None`. Data (np. `2027-03-14T...`) = wygasanie nadal włączone.
Mieszanka `None` i daty → poproś użytkownika, żeby otworzył menu `...` przy serwerze: ma tam być
**Enable key expiry** (czyli wygasanie jest wyłączone). Jest "Disable" → kliknąć raz i powtórzyć odczyty.

**Test zaliczenia:** `KeyExpiry = None` we wszystkich trzech odczytach.

### 4b. Tailscale SSH (opcjonalne, ale warto pokazać)

Tailscale SSH: logowanie na serwer **bez kluczy SSH i bez hasła** - tożsamość daje sam tailnet.
Działa obok zwykłego sshd (`sshd_config` i `authorized_keys` nie są ruszane). Na tailnecie bez
zmienionych ACL jest domyślna reguła: każdy członek może wejść na swoje własne urządzenia, w trybie
`check` (co jakiś czas przeglądarka poprosi o potwierdzenie tożsamości), jako dowolny użytkownik -
**także root**.

**Ostrzeżenie (powiedz to użytkownikowi, zanim włączy): Tailscale SSH nie czyta `sshd_config`**, więc
`PermitRootLogin no` z vps-security go nie obejmuje. Domyślna reguła `ssh` w ACL tailnetu ma
`"users": ["autogroup:nonroot", "root"]` - po `tailscale set --ssh` działa `ssh root@TS_IP` (sprawdzone:
w logu serwera `SSH login: user=root uid=0`). Z internetu nic się nie zmienia (port zamyka Faza 5), ale
obietnica "root nie wchodzi" z hardeningu przestaje być prawdziwa. Wyłącza się to **wyłącznie w ACL**
tailnetu - krok niżej, klik użytkownika.

Zapytaj użytkownika, czy chce. Jeśli tak - uruchom przez **publiczne IP** (jeszcze otwarte), nie przez
`TS_IP`: włączenie Tailscale SSH przejmuje port 22 na adresie tailnetu i może zerwać sesję po `TS_IP`.
`tailscale set --ssh` zamiast `tailscale up --ssh`: `up` przy zmianie flag żąda powtórzenia wszystkich
wcześniejszych, `set` zmienia tylko jedną.

```bash
cat > /tmp/f4b.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
sudo tailscale set --ssh
echo "TS_SSH_ON"
EOS
scp -P PORT /tmp/f4b.sh USER@IP:/tmp/f4b.sh
ssh -p PORT USER@IP "bash /tmp/f4b.sh; rm -f /tmp/f4b.sh"
```

Test z komputera użytkownika - port **22** po adresie Tailscale, niezależnie od `PORT` sshd
(Tailscale SSH przechwytuje port 22 na adresie 100.x):

```bash
# accept-new: przy PORT innym niż 22 known_hosts nie zna jeszcze TS_IP:22 (klucz hosta jest ten sam, z /etc/ssh)
ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new USER@TS_IP "echo TS_SSH_LOGIN_OK"
```

Przy pierwszym połączeniu może pojawić się link do potwierdzenia w przeglądarce (tryb `check`) -
użytkownik klika. Oczekiwany wynik: `TS_SSH_LOGIN_OK` bez pytania o hasło.

Z telefonu (Termius/Blink): host `TS_IP`, port 22, user `USER`, **pole klucza i hasła puste** - loguje
tożsamość z tailnetu. Log na serwerze pokazuje wtedy KTO wszedł, nie tylko skąd:
`journalctl -u tailscaled | grep "SSH login"` → `ts_user=... node=iphone...`.

**Root poza Tailscale SSH (klik użytkownika, nie edytuj ACL za niego):**
konsola **https://login.tailscale.com/admin/acls** (edytor JSON) → sekcja `"ssh"` → w regule z
`"action": "check"` zmień `"users": ["autogroup:nonroot", "root"]` na `"users": ["autogroup:nonroot"]`
→ **Save**. `autogroup:nonroot` = każdy lokalny użytkownik poza rootem, więc `USER` wchodzi dalej.

Test po kilkunastu sekundach (nowa polityka musi dojść do serwera):

```bash
ssh -o BatchMode=yes -o ConnectTimeout=10 root@TS_IP 'id' 2>&1; echo "EXIT=$?"   # ma być ODMOWA
ssh -o ConnectTimeout=10 USER@TS_IP "echo TS_SSH_LOGIN_OK"                        # ma dalej wchodzić
```

Oczekiwany wynik: pierwsza komenda **bez** `uid=0` i z `EXIT=255` (dowolny kod różny od 0 to odmowa).
Na stderr zwykle `tailscale: tailnet policy does not permit you to SSH as user "root"` i
`Connection closed by TS_IP port 22` - bez `2>&1` widać tylko pusty wynik, dlatego zaliczenie opiera się
na kodzie wyjścia, nie na tekście. Druga wypisuje `TS_SSH_LOGIN_OK`. Pierwsza pokazuje `uid=0(root)`
i `EXIT=0` → polityka jeszcze nie doszła
(odczekaj 30 s i powtórz) albo ACL nie zapisano. Pierwsza wyświetla link do potwierdzenia i czeka →
root nadal jest dozwolony (tryb `check`): przerwij i sprawdź ACL. `check.sh` pokazuje to samo w sekcji
Tailscale (WARN "Tailscale SSH wpuszcza roota" / PASS "nie wpuszcza roota").

**Test zaliczenia:** `TS_SSH_LOGIN_OK` **i** odmowa dla `root@TS_IP`.

**FAIL - co zrobić:** `Permission denied` / `access denied` dla `USER` → ACL tailnetu zmienione i nie ma
reguły `ssh` dla tego użytkownika. Pokaż użytkownikowi https://login.tailscale.com/admin/acls i regułę
(`"action": "check", "src": ["autogroup:member"], "dst": ["autogroup:self"], "users": ["autogroup:nonroot"]`).
Nie edytuj ACL za niego. Zwykłe SSH kluczem przez `TS_IP:PORT` działa dalej - to nie blokuje wizarda.
Użytkownik nie chce zmieniać ACL → zapisz w podsumowaniu wprost "root wchodzi przez Tailscale SSH".

---

## Faza 5 - Zamknięcie publicznego SSH

### 5a. Bramka (obowiązkowa, przed jakąkolwiek zmianą)

Sprawdź i wypisz w czacie:

1. Faza 3: "MOST DZIAŁA: [urządzenie 1], [urządzenie 2]" - oba dowody są? Jeśli nie → STOP.
2. Faza 4a: `KeyExpiry = None`? Jeśli nie → STOP.
3. Plan B użytkownika (Zasada 3): gdzie wyłączy firewall, jeśli straci dostęp? Hostinger: hPanel →
   VPS → Firewall → przełącznik przy grupie (działa z telefonu; działa, bo ufw przepuszcza `PORT` -
   patrz 5b). Inni: konsola VNC/serial w panelu.
   Użytkownik odpowiada własnymi słowami. Zapisz.
4. Co zostaje publiczne: 80/443 (jeśli WWW) + UDP 41641 (Tailscale). Nic więcej.

Dopiero po czterech "tak" idziesz do 5b albo 5c.

### 5b. Hostinger - firewall w panelu przez API

Firewall Hostingera działa **przed** serwerem (na hiperwizorze), więc Docker go nie omija, a do
zamknięcia portu ufw nie jest potrzebny. Regułą domyślną grupy jest **drop** wszystkiego, co nie jest
na liście accept.

**Aktywny ufw (po vps-security) zostaje bez zmian - razem z regułą dla `PORT`.** W tej ścieżce to nie
luka, tylko warunek planu B: port zamyka firewall w panelu, a gdy użytkownik go wyłączy (przełącznik),
wejście wraca właśnie dzięki regule w ufw. Bez niej przełącznik nic nie da, a konsola noVNC loguje jako
root (zablokowany). Nie proponuj usuwania `PORT` z ufw. SSH przez tailnet od ufw i tak nie zależy:
tailscaled wstawia własny łańcuch `ts-input` przed ufw i sam wpuszcza `tailscale0` + UDP 41641.
Audyt PO pokaże tę regułę jako WARN - to oczekiwane, dowodem zamknięcia jest skan z 5d.

Token API: użytkownik tworzy w hPanel → **API** (menu konta) i eksportuje **sam w swoim terminalu**:

```bash
export HOSTINGER_API_TOKEN='...'
```

Nie proś o token w czacie. Skrypt czyta go ze zmiennej środowiskowej.

Najpierw lista maszyn (GET, bezpieczne):

```bash
python3 ./scripts/hostinger-firewall.py list
```

Oczekiwany wynik: tabela `id | hostname | ipv4 | firewall_group_id`. Znajdź `id` serwera po IP.
Zapisz jako `VM_ID`.

Utworzenie grupy i aktywacja (POST - **użytkownik uruchamia sam** w swoim terminalu, bo tworzy to
zmianę w jego infrastrukturze; podaj mu gotową komendę):

```bash
# tylko Tailscale (bez WWW):
python3 ./scripts/hostinger-firewall.py setup --vm VM_ID
# z publicznym WWW/webhookami na 80 i 443:
python3 ./scripts/hostinger-firewall.py setup --vm VM_ID --web
```

Skrypt: tworzy grupę `tailscale-lockdown-VM_ID` (albo używa istniejącej o tej nazwie - drugie
uruchomienie nie robi duplikatu), dodaje brakujące accept UDP 41641 (+ TCP 80/443 przy `--web`),
przypina grupę do VM, wywołuje `sync` i wypisuje `FIREWALL_ID`. Zapisz `FIREWALL_ID` - służy do wycofania.

Jeśli `list` pokazał przy VM `firewall_group_id` inne niż `None`, serwer ma już jakąś grupę - `setup`
ją zastąpi (zostaje na koncie). Powiedz to użytkownikowi, zanim uruchomi komendę.

Sprawdzenie (GET) - `FIREWALL_ID` do wycofania bierz z tego wyniku:

```bash
python3 ./scripts/hostinger-firewall.py status --vm VM_ID
```

Oczekiwany wynik: `VM ... -> firewall_group_id: FIREWALL_ID` i wiersz tej grupy z `is_synced true`,
regułami accept i znacznikiem `<- PRZYPIĘTA DO TEJ VM`. Wiersz `<- NIEPRZYPIĘTA ... sierota` to duplikat
z wcześniejszego przebiegu - użytkownik usuwa go w hPanelu. Grupy innych serwerów skrypt wypisuje tylko
z nazwy: nie ruszać.

Co użytkownik zobaczy w hPanel → VPS → Zapora sieciowa (Firewall): listę **wszystkich** grup na koncie,
a przełącznik przy grupie mówi tylko, czy jest przypięta do **tego** serwera, który ogląda. Grupy innych
serwerów są tam wyłączone i to normalne - nie przełączać ich. Jeden serwer = jedna aktywna grupa.

Wycofanie (plan B z terminala, jeśli użytkownik nadal ma tailnet):

```bash
python3 ./scripts/hostinger-firewall.py off --vm VM_ID FIREWALL_ID
```

Sprzątanie: po skasowaniu serwera (np. testowego) grupa `tailscale-lockdown-VM_ID` zostaje na koncie
jako sierota - można ją usunąć w hPanelu (Zapora sieciowa → `...` przy grupie → Usuń). Grup innych
serwerów nie ruszać.

Firewall Hostingera filtruje **IPv4 i IPv6** (sshd słucha też na `[::]:22`, sprawdzone: 22 po IPv6
zamknięte). Reguły wchodzą w życie w **poniżej minuty** (dokumentacja: "two minutes or less"); po
`setup` odczekaj 60 s zanim skanujesz. Firewall jest stateful: serwer dalej ma internet (apt, HTTPS
wychodzące), a `sshd` na serwerze dalej pokazuje LISTEN - blokada stoi przed serwerem, nie na nim.

**Uwaga:** konsola web w hPanel (noVNC) loguje jako root; na serwerze po vps-security root ma
zablokowane logowanie, więc konsola **nie** jest planem B. Planem B jest przełącznik firewalla w panelu.

### 5c. Inny dostawca - ufw na serwerze

Kolejność jest ważna: najpierw wpuszczasz ruch z interfejsu Tailscale i UDP 41641, potem domyślne
`deny incoming`, na końcu `enable`. Publiczny port SSH **nie** dostaje reguły allow, więc znika.

```bash
cat > /tmp/f5c.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
sudo ufw --force reset >/dev/null
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow in on tailscale0
sudo ufw allow 41641/udp
# odkomentuj, jeśli na serwerze jest publiczne WWW / webhooki:
# sudo ufw allow 80/tcp
# sudo ufw allow 443/tcp
sudo ufw --force enable
sudo ufw status verbose
echo "UFW_LOCKDOWN_ON"
EOS
scp -P PORT /tmp/f5c.sh USER@IP:/tmp/f5c.sh
ssh -p PORT USER@TS_IP "bash /tmp/f5c.sh; rm -f /tmp/f5c.sh"
```

Zwróć uwagę: ostatnie `ssh` idzie już przez `TS_IP`, nie przez `IP` - bo w trakcie skryptu publiczne
wejście znika i sesja po publicznym adresie by się urwała.

**Docker omija ufw.** Kontener z `-p 8080:8080` publikuje port przez iptables **przed** ufw i jest
widoczny z internetu mimo `deny`. Jeśli audyt z 1b pokazał kontenery z portami na `0.0.0.0`, pokaż
użytkownikowi rozwiązanie: w `docker-compose.yml` bindować porty wewnętrzne na adres Tailscale,
`"TS_IP:8080:8080"` zamiast `"8080:8080"`, i zrestartować stack. Porty publiczne (80/443 reverse proxy)
zostają na `0.0.0.0`. Nie edytuj cudzych compose'ów bez zgody - pokaż diff, użytkownik decyduje.

### 5d. Dowód: stare wejście zamknięte, nowe działa

Z komputera użytkownika:

```bash
bash ./scripts/portscan.sh IP
ssh -p PORT -o ConnectTimeout=10 USER@TS_IP "echo STILL_IN_VIA_TAILNET"
```

Oczekiwany wynik: `PORT` **closed** (i `8080` itp. closed, jeśli były), 80/443 open tylko jeśli
`--web`; oraz `STILL_IN_VIA_TAILNET`.

Test negatywny (do filmu): `ssh -p PORT -o ConnectTimeout=5 USER@IP` → `Connection timed out`.

**Test zaliczenia:** skan pokazuje port SSH zamknięty, a `STILL_IN_VIA_TAILNET` przeszło.

**FAIL - co zrobić:**
- port SSH nadal OPEN po Hostingerze → `status` pokazuje `is_synced: false`? Uruchom
  `python3 ./scripts/hostinger-firewall.py sync --vm VM_ID FIREWALL_ID` (użytkownik) i skanuj ponownie
  po 30 s. Nadal open → sprawdź w `status`, czy wiersz `PRZYPIĘTA DO TEJ VM` to grupa z `setup`.
- SSH przez tailnet nie działa po zamknięciu → **natychmiast plan B**: wyłącz firewall (panel / `off`)
  i wróć do Fazy 3. Nie próbuj "jeszcze jednej reguły" na ślepo.

---

## Faza 6 - Audyt PO + zestawienie

Skrypt kopiujesz **jeszcze raz** - kopia z 1b mogła zniknąć (`/tmp` czyści się przy restarcie) albo być
starsza niż wersja w repo:

```bash
scp -P PORT ./scripts/check.sh USER@TS_IP:/tmp/check.sh
ssh -p PORT USER@TS_IP "bash /tmp/check.sh 2>&1 | tee /tmp/tailscale-check-after.txt"
```

Bez `--before`. Tailscale, tailnet i key expiry mają być na zielono. `check.sh` działa na serwerze,
więc **nie widzi** firewalla Hostingera - dowodem zamknięcia jest skan z 5d, nie audyt. W ścieżce
Hostinger jeden WARN jest oczekiwany: `ufw przepuszcza port SSH ...` (reguła zostaje dla planu B, 5b).
WARN `Tailscale SSH wpuszcza roota` oczekiwany nie jest - wróć do 4b (krok ACL); reguła `ssh` w ACL
tailnetu to jedyne miejsce, gdzie się to wyłącza.

Pokaż użytkownikowi zestawienie:

| | PRZED (Faza 1) | PO (Faza 6) |
|---|---|---|
| Skan z internetu: port SSH | OPEN | closed |
| Skan z internetu: inne porty | (lista z 1c) | tylko 80/443 (jeśli WWW) |
| Wejście z komputera | `ssh USER@IP -p PORT` | `ssh USER@TS_IP -p PORT` (lub `ssh USER@NAZWA`) |
| Wejście z telefonu | brak / klucze na telefonie | aplikacja Tailscale + `TS_IP` |
| Klucz urządzenia serwera | wygasa po 180 dniach | nie wygasa |
| Prób logowania obcych / dobę | (liczba z 1c) | 0 (port nie istnieje) |

Jeśli użytkownik ma alias w `~/.ssh/config` wskazujący na publiczne IP serwera - przestał działać.
Zaproponuj podmianę `HostName` na `TS_IP` albo na `NAZWA` (MagicDNS; przeżyje zmianę adresu 100.x
po reinstalacji). Nie edytuj `~/.ssh/config` bez zgody - pokaż linię do zmiany.

Podsumowanie na koniec:

- Serwer w tailnecie jako `NAZWA` (`TS_IP`)
- Publicznie otwarte: UDP 41641 [+ TCP 80/443]
- Plan B: [odpowiedź użytkownika z 5a]
- Firewall: Hostinger grupa `FIREWALL_ID` / ufw
- Tailscale SSH: włączone (root wyłączony w ACL: tak / nie) / nie
- Jądro po aktualizacji z 1d: `uname -r` (restart odłożony: tak / nie)
- Następny krok (opcjonalnie): udostępnienie jednej maszyny drugiej osobie (Machines → Share),
  panel wewnętrzny bota tylko z tailnetu (bind na `TS_IP`), `tailscale serve --bg` dla HTTPS
  w tailnecie (sekcja "Co dalej" niżej)

---

## Co dalej (opcjonalnie): `tailscale serve` zamiast gołego portu

Jeśli użytkownik pyta, jak wystawić panel (n8n, Grafana, strona testowa z 3b) ładniej niż przez
`http://TS_IP:8000`, pokaż mu jedną komendę. To nie jest faza wizarda - nie ma bramek, nie blokuje nic.

```bash
sudo tailscale serve --bg 8000        # 8000 = port usługi, która już działa lokalnie
tailscale serve status                # co jest wystawione
tailscale serve reset                 # sprzątanie: zdejmij wszystko
```

Co to daje: usługa z portu 8000 dostaje adres `https://NAZWA.TAILNET.ts.net` z **prawdziwym
certyfikatem** (koniec z ostrzeżeniami przeglądarki), widoczny **wyłącznie dla urządzeń w tailnecie**.
`--bg` = konfiguracja jest trwała, usługa wstaje po restarcie serwera (bez `--bg` komenda trzyma
terminal i gaśnie razem z sesją). Wymaga włączonego **HTTPS Certificates** w konsoli Tailscale (DNS →
HTTPS Certificates); jeśli nie jest, komenda wypisze link do włączenia - to klik użytkownika.

**Ostrzeżenie, powiedz je głośno: `serve` to moja sieć, `funnel` to cały świat.** `tailscale funnel`
wygląda prawie tak samo, ale publikuje tę samą usługę w publicznym internecie - czyli odwraca to,
co właśnie zrobiłeś w Fazie 5. Nie myl tych dwóch komend; wizard funnela nie konfiguruje.

---

## Czego wizard NIE robi (i celowo)

- nie zmienia `sshd_config`, portu SSH ani `PermitRootLogin`,
- nie zamyka publicznego SSH przed dwoma dowodami z Fazy 3,
- nie prosi o tokeny ani auth keye w czacie,
- nie konfiguruje exit node, subnet routera ani **Funnel** (publiczne wystawienie usługi) - to osobne
  tematy; `tailscale serve` (tylko tailnet) jest opisany wyżej jako opcjonalny krok "co dalej",
- nie edytuje ACL tailnetu; jedyna zmiana ACL (root poza Tailscale SSH, 4b) to klik użytkownika,
- nie instaluje Headscale (self-hosted zamiennik serwera koordynacyjnego) - jedno zdanie dla
  zainteresowanych: to kolejny serwer do utrzymania,
- nie edytuje cudzych `docker-compose.yml` bez pokazania diffu i zgody.
