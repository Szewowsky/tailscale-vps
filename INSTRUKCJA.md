# Zamykam serwer VPS na świat - krok po kroku

Nie musisz być programistą. Potrzebujesz tylko:
- VPS z Ubuntu 22.04 / 24.04 i dostępu SSH kluczem
- Darmowego konta Tailscale (logowanie Google, GitHub, Microsoft albo Apple)
- Tailscale na komputerze (Mac: App Store; Windows/Linux: tailscale.com/download) zalogowanego tym kontem
- Telefonu z aplikacją Tailscale (do testu "z LTE") - albo drugiego komputera
- Terminal na komputerze (Terminal na Macu, PowerShell na Windows)
- Około 30 minut

## Krok zero: zabezpiecz serwer

Ten poradnik **nie robi hardeningu** (użytkownik nie-root, klucze SSH, fail2ban). Jeśli Twój serwer
produkcyjny jest świeży, zacznij tutaj i wróć:

**https://szewowsky.github.io/vps-security/**

Na testowej maszynie (jak w filmie) można przejść ten poradnik od razu, jako root.

## Złota zasada

**Najpierw budujesz nowy most, sprawdzasz, że przenosi ciężar, i dopiero potem rozbierasz stary.**
Publiczny port SSH zamykasz w Kroku 5 dopiero po tym, jak w Kroku 3 wszedłeś na serwer przez tailnet
z **dwóch** urządzeń.

## Zanim zaczniesz

Podłącz się do serwera:

```
ssh twoj_user@TWOJE_IP
```

Inny port SSH (np. 2222):

```
ssh -p 2222 twoj_user@TWOJE_IP
```

Jeśli zobaczysz `REMOTE HOST IDENTIFICATION HAS CHANGED`, a serwer był niedawno reinstalowany:
`ssh-keygen -R TWOJE_IP` i spróbuj ponownie.

## Sprawdź, jak jest teraz (audyt PRZED)

Ze swojego komputera, z katalogu tego repo:

```
scp ./scripts/check.sh twoj_user@TWOJE_IP:/tmp/
ssh twoj_user@TWOJE_IP "bash /tmp/check.sh --before"
```

Sekcja "Tailscale" będzie na żółto - to normalne, jeszcze go nie ma.

Skan portów **z Twojego komputera** (to widzi internet):

```
bash ./scripts/portscan.sh TWOJE_IP
```

Zapisz sobie wynik. Port SSH będzie `OPEN`. Do tego wrócisz na końcu. Masz `nmap`? Ładniej:
`nmap -Pn -p 22,80,443 TWOJE_IP`. Pełny `nmap -Pn TWOJE_IP` trwa ok. 50 s teraz i ok. 7 minut po
zamknięciu - serwer, który nie odpowiada, marnuje czas skanera. Inne porty jako `filtered` to nie
firewall serwera, tylko zgubione po drodze odpowiedzi - liczy się to, co OPEN.

Ciekawostka: ile prób logowania obcych było w ostatniej dobie?

```
ssh -t twoj_user@TWOJE_IP "sudo journalctl -u ssh --since '24 hours ago' | grep -c -E 'Failed password|Invalid user|Connection closed by authenticating user'"
```

Bez `sudo` zwykły użytkownik nie widzi logów sshd i dostaje `0`. Wynik obejmuje też Twoje własne
nieudane próby (np. z hardeningu).

---

## Krok 1: Tailscale na komputerze i telefonie

**Po co?** Tailscale buduje prywatną sieć (tailnet) z Twoich urządzeń. Serwer dołączy do niej w Kroku 2,
ale sieć musi już istnieć.

1. Komputer: zainstaluj Tailscale, zaloguj się kontem (Google/GitHub/Microsoft/Apple).
2. Telefon: aplikacja Tailscale, to samo konto.
3. Sprawdź na komputerze:

```
tailscale status
```

Mac z App Store nie ma `tailscale` w PATH - użyj pełnej ścieżki:

```
/Applications/Tailscale.app/Contents/MacOS/Tailscale status
```

Masz widzieć swój komputer i telefon z adresami `100.x.y.z`.

---

## Krok 2: Tailscale na serwerze

**Po co?** Serwer dostaje własny adres `100.x.y.z`, widoczny tylko dla Twoich urządzeń.

Na serwerze:

```
curl -fsSL https://tailscale.com/install.sh | sh
sudo systemctl enable --now tailscaled
sudo tailscale up --hostname NAZWA
```

`NAZWA` to nazwa serwera w tailnecie, np. `vps-boty` (małe litery, bez spacji). Komenda przez
**ok. 20 sekund nic nie wypisuje** (wygląda na zawieszoną, nie przerywaj), potem pokazuje link
`https://login.tailscale.com/a/...` - otwórz go w przeglądarce na komputerze, zaloguj się tym samym
kontem, kliknij **Connect**. Terminal odblokuje się sam po kilkunastu sekundach.

Sprawdź adres serwera w tailnecie i zapisz go (dalej: `TS_IP`):

```
tailscale ip -4
```

Na komputerze `tailscale status` pokazuje teraz także `NAZWA`.

---

## Krok 3: Test nowego mostu (DWA urządzenia)

**Po co?** To jest dowód, że masz drugie wejście. Bez niego nie zamykasz pierwszego.

Z komputera, przez prywatny adres:

```
tailscale ping TS_IP
ssh -p PORT twoj_user@TS_IP
```

`pong ... via 1.2.3.4:41641` = połączenie bezpośrednie. `via DERP(waw)` = przez przekaźnik Tailscale
(działa, wolniej; zwykle po chwili przechodzi w bezpośrednie).

Z telefonu, **na LTE** (Wi-Fi wyłączone), Tailscale włączony:

- wariant A: aplikacja SSH (Termius, Blink) → `twoj_user@TS_IP`, port `PORT`, **własnym kluczem
  telefonu**: wygeneruj go w aplikacji (Termius: Keychain → Generate Key), a jego publiczną część
  (linia `ssh-ed25519 ...`) dopisz z komputera do `~/.ssh/authorized_keys` na serwerze. "Export to host"
  nie zadziała, jeśli logowanie hasłem jest wyłączone,
- wariant B: na serwerze uruchom na 2 minuty stronę testową tylko na adresie Tailscale
  i otwórz w przeglądarce telefonu `http://TS_IP:8000`:

```
cd /tmp && echo '<h1>Jesteś w tailnecie</h1>' > index.html && timeout 120 python3 -m http.server 8000 --bind TS_IP
```

Ten sam adres z publicznym IP (`http://TWOJE_IP:8000`) **nie** zadziała - strona słucha tylko na
adresie Tailscale. To jest cały pomysł w jednym obrazku.

Masz dwa udane wejścia? Idź dalej. Nie masz? Nie zamykaj niczego.

---

## Krok 4: Wyłącz wygasanie klucza (i opcjonalnie SSH bez kluczy)

**Po co?** Domyślnie klucz urządzenia wygasa po 180 dniach. Laptop odnowi go sam przy logowaniu,
serwer nie - wypada z sieci, a jeśli publiczne SSH jest już zamknięte, zostajesz bez wejścia.

1. https://login.tailscale.com/admin/machines → wiersz `NAZWA` → `...` → **Disable key expiry**.
2. Sprawdź na serwerze:

```
tailscale status --json | grep KeyExpiry
```

Brak linii albo `"KeyExpiry": null` = wyłączone. Data = nadal włączone. Sprawdź jeszcze raz po pół
minucie - tuż po kliknięciu wynik bywa chwilowy (drugi klik w tym samym menu włącza wygasanie z powrotem).

**Opcjonalnie - Tailscale SSH** (logowanie bez kluczy, tożsamość daje tailnet; zwykły sshd zostaje).
Uruchom w sesji po **publicznym IP**, bo przełączenie może zerwać sesję po adresie Tailscale:

```
sudo tailscale set --ssh
```

Z telefonu (Termius): host `TS_IP`, port 22, pole klucza i hasła puste. Na serwerze
`journalctl -u tailscaled | grep "SSH login"` pokazuje, KTO wszedł (konto + urządzenie), nie tylko skąd.

Z komputera: `ssh twoj_user@TS_IP` (port 22, niezależnie od portu sshd). Przy pierwszym wejściu może
poprosić o potwierdzenie w przeglądarce.

---

## Krok 5: Zamknij publiczne SSH

### Zanim cokolwiek zamkniesz

- Krok 3: dwa udane wejścia przez tailnet? ✅
- Krok 4: key expiry wyłączone? ✅
- Plan B: wiesz, gdzie wyłączysz firewall, jeśli stracisz dostęp? Hostinger: hPanel → VPS → Firewall
  → przełącznik przy grupie (działa z telefonu). Inni dostawcy: konsola VNC/serial w panelu.
- Co ma zostać publiczne? WWW/webhooki na 80/443 - tak/nie.

### Wariant A: Hostinger (firewall w panelu, przez API)

Firewall Hostingera działa **przed** serwerem, więc Docker go nie omija. Token: hPanel → **API**.
W swoim terminalu (nie wklejaj tokena nigdzie indziej):

```
export HOSTINGER_API_TOKEN='...'
python3 ./scripts/hostinger-firewall.py list
```

Znajdź `id` serwera po IP. Potem:

```
python3 ./scripts/hostinger-firewall.py setup --vm ID_SERWERA
```

Z publicznym WWW na 80/443 dodaj `--web`. Skrypt tworzy grupę `tailscale-lockdown-ID` (przy
ponownym uruchomieniu używa tej samej), wpuszcza UDP 41641 (+ 80/443), aktywuje ją na serwerze
i wypisuje `FIREWALL_ID`. Wszystko inne (w tym SSH) jest odrzucane. `status --vm ID_SERWERA` pokazuje,
która grupa jest przypięta do serwera.

W hPanelu (VPS → Zapora sieciowa) widzisz wszystkie grupy z konta; przełącznik mówi tylko, czy grupa
jest przypięta do oglądanego serwera. Grupy innych serwerów są tam wyłączone - tak ma być.

Reguły wchodzą w życie w poniżej minuty; firewall filtruje IPv4 i IPv6, ruch wychodzący serwera
(apt, HTTPS) działa dalej.

To samo ręcznie w hPanel: VPS → Firewall → Create → reguły accept UDP 41641 (+ TCP 80, 443) →
Activate na serwerze.

Wycofanie: przełącznik w panelu albo
`python3 ./scripts/hostinger-firewall.py off --vm ID_SERWERA FIREWALL_ID`.

**ufw na serwerze zostaw jak jest, z regułą dla portu SSH.** To dzięki niej przełącznik w panelu
przywraca dostęp (konsola web loguje jako root, a ten po hardeningu nie wchodzi). Przez tailnet
wchodzisz niezależnie od ufw - Tailscale sam wpuszcza swój ruch przed regułami ufw.

### Wariant B: inny dostawca (ufw na serwerze)

Zaloguj się **przez tailnet** (`ssh twoj_user@TS_IP`), bo w trakcie publiczne wejście zniknie:

```
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow in on tailscale0
sudo ufw allow 41641/udp
# tylko jeśli masz publiczne WWW / webhooki:
# sudo ufw allow 80/tcp
# sudo ufw allow 443/tcp
sudo ufw --force enable
sudo ufw status verbose
```

**Docker omija ufw.** Kontener z `-p 8080:8080` jest widoczny z internetu mimo `deny`. Porty
wewnętrzne binduj na adres Tailscale: w `docker-compose.yml` `"TS_IP:8080:8080"` zamiast
`"8080:8080"`, potem `docker compose up -d`. Publiczne 80/443 zostają na `0.0.0.0`.

### Dowód

Z komputera:

```
bash ./scripts/portscan.sh TWOJE_IP
ssh -p PORT twoj_user@TS_IP "echo DALEJ_WCHODZE"
```

Port SSH `closed`, `DALEJ_WCHODZE` na ekranie. Stare wejście po publicznym IP:
`ssh -p PORT twoj_user@TWOJE_IP` → `Connection timed out`. O to chodziło.

---

## Krok 6: Audyt PO

Skopiuj skrypt jeszcze raz (kopia sprzed godziny mogła zniknąć z `/tmp`):

```
scp -P PORT ./scripts/check.sh twoj_user@TS_IP:/tmp/
ssh -p PORT twoj_user@TS_IP "bash /tmp/check.sh"
```

Tailscale, tailnet i key expiry na zielono. Audyt działa na serwerze, więc **nie widzi** firewalla
Hostingera - dowodem zamknięcia jest skan z Kroku 5.

## Gotowe!

- Wejście z komputera: `ssh -p PORT twoj_user@TS_IP` (albo `ssh twoj_user@NAZWA`, jeśli MagicDNS)
- Wejście z telefonu: aplikacja Tailscale + `TS_IP`
- Publicznie otwarte: UDP 41641 (+ 80/443, jeśli WWW)
- Zgubiony laptop: Machines → urządzenie → `...` → Remove. Reszta działa dalej

**Co dalej (osobne tematy):** udostępnienie jednej maszyny drugiej osobie (Machines → Share),
panel bota tylko z tailnetu (bind na `TS_IP`), exit node (telefon wychodzi do internetu przez serwer).

---

## Coś poszło nie tak?

### 1. Zamknąłem port i nie mogę wejść przez tailnet

Plan B: wyłącz firewall (Hostinger: przełącznik w panelu, z telefonu też; skrypt `off`; inni: ufw
z konsoli VNC `sudo ufw disable`). Wróć do Kroku 3 i znajdź, dlaczego most nie działa. Najczęściej:
Tailscale na serwerze wylogowany (`tailscale status` → `NeedsLogin`), inne konto, telefon na Wi-Fi.

### 2. `tailscale ping` mówi `via DERP(...)` i nigdy nie przechodzi w direct

UDP 41641 zablokowane po drodze (firewall bez tej reguły). Działa, tylko wolniej. Dodaj accept
UDP 41641 i sprawdź ponownie po minucie.

### 3. Konsola web Hostingera nie loguje na serwer

Konsola (noVNC) loguje jako root. Po vps-security root ma zablokowane logowanie, więc konsola
**nie** jest planem B. Planem B jest firewall w panelu.

### 4. Po miesiącach serwer zniknął z tailnetu

Key expiry było włączone (Krok 4 pominięty). Wejdź planem B, `sudo tailscale up --force-reauth`,
kliknij link, tym razem wyłącz key expiry.

### 5. Kontener Dockera widać z internetu mimo ufw

Docker pisze własne reguły iptables przed ufw. Bind portu na `TS_IP` (Krok 5, wariant B) albo
firewall dostawcy (wariant A).

### 6. "Tailscale nie jest open source, widzi mój ruch"

Klient jest open source. Serwer koordynacyjny (chmura Tailscale) zna klucze publiczne, adresy i nazwy
urządzeń - kojarzy pary. Sam ruch idzie bezpośrednio między Twoimi urządzeniami, zaszyfrowany
WireGuardem, przez ich serwer przechodzi tylko w trybie przekaźnika (DERP) i nadal zaszyfrowany.
Kto nie chce chmury, ma Headscale - ale to kolejny serwer do utrzymania.
