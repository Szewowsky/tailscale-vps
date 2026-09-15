# AGENTS.md - instrukcja dla agenta (Codex, Claude Code i inne)

To repo to wizard schowania serwera VPS za prywatną siecią Tailscale. Jedyne źródło prawdy dla agenta:
**`.claude/commands/tailscale-setup.md`** - przeczytaj go w całości i prowadź użytkownika fazami
F0 -> F6 dokładnie w tej kolejności, z testem zaliczenia po każdej fazie.

Zasady, których nie wolno złamać (pełna lista w wizardzie, sekcja "ZASADY BEZPIECZEŃSTWA"):

1. **Nie zamykaj publicznego portu SSH (Faza 5), dopóki Faza 3 nie ma dwóch udanych logowań
   przez tailnet** (komputer użytkownika + drugie urządzenie). Bez wyjątków, także "bo się spieszymy".
2. Nie dotykaj `sshd_config`, nie zmieniaj portu SSH, nie wyłączaj sshd. Tailscale SSH (Faza 4b) jest
   opcjonalny i działa obok zwykłego sshd, nie zamiast.
3. Nie wklejaj do czatu tokenów (Hostinger API, auth key Tailscale). Link autoryzacji `tailscale up`
   i kliknięcia w panelach wykonuje użytkownik sam.
4. Przed zamknięciem 22 użytkownik ma znać swój plan B (firewall z panelu / konsola VNC) - zapytaj i zapisz.
5. Czekaj na wynik każdej komendy. Test fazy nie przeszedł -> STOP, pokaż output, zapytaj.

Audyt: `scripts/check.sh --before` na serwerze przed, `scripts/check.sh` po. Skan z komputera
użytkownika: `scripts/portscan.sh IP` przed i po. Audyt PO ma być bez FAIL.

Komendy z `sudo` na serwerze: zapisz skrypt do pliku lokalnie heredokiem, `scp` na serwer, wykonaj przez
`ssh USER@IP "bash /tmp/plik.sh"`. Nie łącz faz w jedną komendę.
