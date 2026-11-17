#!/usr/bin/env bash
# 0ne//hub — Hysteria 2 / Remnanode. Debian / Ubuntu, root, systemd.
set +x
set -Eeuo pipefail
umask 077
export LC_ALL=C.UTF-8
ROOT=/opt/onehub-hy2
NODE=/opt/remnanode
CERT=/opt/hysteria/certs
NGINX=/etc/nginx/conf.d/onehub-hy2.conf
CRON=/etc/cron.d/onehub-hy2
RED='' GRAY='' RESET=''
[[ ! -t 1 || -n ${NO_COLOR:-} ]] || { RED=$'\033[31m'; GRAY=$'\033[90m'; RESET=$'\033[0m'; }
TMP='' NGINX_STOPPED=0
fail() { printf '\nОшибка: %s\n' "$*" >&2; exit 1; }
note() { printf '\n%s\n' "$*"; }
section() { printf '\n%s──────%s %s %s/%s %s %s──────%s\n' "$RED" "$RESET" "$1" "$RED" "$RESET" "$2" "$RED" "$RESET"; }
ask() { IFS= read -r -p "$2" "$1" < /dev/tty || fail 'Ввод прерван.'; }
secret() { IFS= read -rs -p "$2" "$1" < /dev/tty || fail 'Ввод прерван.'; printf '\n'; }
yes() { local answer; ask answer "$1 [y/N]: "; [[ $answer =~ ^([yY]|[yY][eE][sS])$ ]]; }
finish() {
  local rc=$?
  trap - EXIT
  if (( NGINX_STOPPED )) && [[ -f $ROOT/nginx-was-running ]]; then "$ROOT/acme-post.sh" || true; fi
  [[ -z $TMP ]] || rm -rf -- "$TMP"
  unset SECRET_KEY LICENSE_KEY ONEHUB_LICENSE_KEY
  if (( rc )); then printf '\nУстановка прервана. Для проверки используйте пункт 3, для удаления изменений — пункт 2.\n' >&2; fi
  exit "$rc"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'printf "Ошибка на строке %s (код %s).\n" "$LINENO" "$?" >&2' ERR
banner() {
  cat <<'LOGO'


                                                            ⠈⠛⣀⣀⣀⡀                       ⣀⣀⣀⡀
                                                 ⢀⣿⡿    ⢀⣿⡿   ⣿⣿⣿⡇                     ⠈⠛⣿⣿⣿⡇
                                                 ⣼⣿⠃    ⣼⣿⠃   ⣿⣿⣿⡇                       ⢽⣿⣿⡇
        ⣀⣤⣤⠤⣤⣤⣄⡀  ⢠⣤⣀⣤⣤⡄⣀⣤⣤⣤⣤⡀    ⢀⣠⣤⡴⣤⣤⣄⡀      ⢰⣿⠇    ⢰⣿⠇    ⣿⣿⣿⡇⢀⣤⣤⣤⣤⡀  ⣤⣤⣤⣤⣤  ⣤⣤⣤⣤⣤   ⢽⣿⣿⡇⣠⣤⣤⣤⣄⡀
      ⢠⣾⣿⡿⠁  ⢻⣿⣿⣆  ⠈⣿⣿⣿⡟⠋⠉⠻⣿⣿⣷   ⣰⣿⣿⠏  ⣿⣿⣿⡆    ⢠⣿⡟    ⢠⣿⡟     ⣿⣿⣿⡷⠋⠉⠙⣿⣿⣿⡄  ⠙⣿⣿⣿   ⢹⣿⣿⣿   ⢽⣿⣿⡟⠉⠉⠹⣿⣿⣿⡄
      ⣿⣿⣿⡇   ⢸⣿⣿⣿⡆  ⣿⣿⣿⡇   ⣿⣿⣿  ⢰⣿⣿⣿⠦⠦⠦⠿⠿⠿⠗    ⣼⣿⠁    ⣼⣿⠁     ⣿⣿⣿⡇   ⣿⣿⣿⡇   ⣿⣿⣿   ⢸⣿⣿⣿   ⢽⣿⣿⡇   ⢹⣿⣿⣿
      ⣿⣿⣿⡇   ⢸⣿⣿⣿⠃  ⣿⣿⣿⡇   ⣿⣿⣿  ⠸⣿⣿⣿⡆         ⣸⣿⠃    ⣸⣿⠃      ⣿⣿⣿⡇   ⣿⣿⣿⡇   ⣿⣿⣿   ⢸⣿⣿⣿   ⢽⣿⣿⡇   ⢸⣿⣿⣿
      ⠘⢿⣿⣷⡀  ⣼⣿⣿⠋   ⣿⣿⣿⡇  ⢀⣿⣿⣿⡀  ⠻⣿⣿⣷⣄⣀⢀⣀⣴⠟  ⢠⣿⡏    ⢠⣿⡏       ⣿⣿⣿⣇   ⣿⣿⣿⡇   ⢿⣿⣿⣆⣀⣀⣼⣿⣿⣿⡀  ⣿⣿⣿⣇  ⢀⣿⣿⡿⠃
        ⠉⠛⠛⠖⠛⠛⠉   ⠘⠛⠛⠛⠛⠛  ⠛⠛⠛⠛⠛⠃  ⠈⠙⠛⠻⠛⠛⠋⠁   ⣾⡿     ⣾⡿      ⠈⠛⠛⠛⠛⠛⠛ ⠛⠛⠛⠛⠛⠛  ⠈⠛⠛⠛⠛⠉⠘⠛⠛⠛⠛⠃ ⠿⠋⠈⠛⠛⠚⠛⠛⠉
                                            ⣼⣿⠃    ⣼⣿⠃
                                           ⠐⠛⠋    ⠐⠛⠋


                                                                                                          
LOGO
  printf "\n0ne%s//%shub — Установка Hysteria 2\n\n" "$RED" "$RESET"
}
require_system() {
  [[ $(id -u) == 0 ]] || fail 'Запустите: sudo bash install.sh'
  [[ $(uname -s) == Linux && -f /etc/debian_version ]] || fail 'Поддерживаются Debian и Ubuntu.'
  [[ -d /run/systemd/system ]] || fail 'Нужен работающий systemd.'
  command -v flock >/dev/null || fail 'Нужен flock (пакет util-linux).'
  exec 9>/run/lock/onehub-hy2.lock
  flock -n 9 || fail 'Другой экземпляр установщика уже запущен.'
}
valid_domain() {
  [[ ${#1} -le 253 && $1 == *.* && $1 != *[!a-zA-Z0-9.-]* && $1 != .* && $1 != *. ]] || return 1
  local label; local -a labels
  IFS=. read -ra labels <<< "$1"
  for label in "${labels[@]}"; do
    [[ ${#label} -ge 1 && ${#label} -le 63 && $label != -* && $label != *- ]] || return 1
  done
  [[ ! $1 =~ ^[0-9.]+$ ]]
}
resolve() {
  python3 - "$1" <<'PY'
import socket,sys,ipaddress
try:
    host=sys.argv[1]
    try: ips={str(ipaddress.ip_address(host))}
    except ValueError: ips={a[4][0] for a in socket.getaddrinfo(host,None,0,socket.SOCK_STREAM)}
    if not ips: raise ValueError()
    for ip in sorted(ips):
        address=ipaddress.ip_address(ip)
        if address.is_unspecified or address.is_multicast or address.is_loopback: raise ValueError()
        print(address)
except (ValueError, OSError): sys.exit(1)
PY
}
collect() {
  section 01 'Настройка ноды'
  while :; do ask DOMAIN 'Домен ноды: '; DOMAIN=${DOMAIN,,}; valid_domain "$DOMAIN" && break; note 'Укажите DNS-имя, без https:// и пути (IDN — в punycode).'; done
  while :; do
    ask NODE_PORT 'Порт ноды [2222 — Enter]: '; NODE_PORT=${NODE_PORT:-2222}
    if [[ $NODE_PORT =~ ^[0-9]{1,5}$ ]] && (( 10#$NODE_PORT > 0 && 10#$NODE_PORT < 65536 )); then
      NODE_PORT=$((10#$NODE_PORT))
      [[ $NODE_PORT != 80 && $NODE_PORT != 443 ]] && break
    fi
    note 'Укажите порт 1–65535, кроме 80 и 443.'
  done
  ask PANEL 'IP или домен панели: '
  [[ $PANEL != *[!a-zA-Z0-9.:-]* && -n $PANEL ]] || fail 'Панель: нужен IP или домен без URL и порта.'
  secret SECRET_KEY "SECRET_KEY ноды ${GRAY}(ввод скрыт, после вставки нажмите Enter)${RESET}: "
  [[ -n $SECRET_KEY && $SECRET_KEY != *$'\r'* ]] || fail 'SECRET_KEY пуст или содержит CR.'
  section 02 'Выбор HTML макета'
  local i
  for ((i=0;i<${#NAMES[@]};i++)); do printf '%2s) %s — %s\n' "$((i+1))" "${NAMES[i]}" "${DESCRIPTIONS[i]}"; done
  while :; do
    ask CHOICE 'Ваш выбор [1–10]: '
    [[ $CHOICE =~ ^([1-9]|10)$ ]] && break
  done
  INDEX=$((CHOICE-1)); RANDOMIZE=0
  if yes 'Рандомизировать цветовую палитру?'; then RANDOMIZE=1; fi
  LICENSE_KEY=${ONEHUB_LICENSE_KEY:-}
  if [[ -z $LICENSE_KEY ]]; then secret LICENSE_KEY 'Лицензионный ключ 0ne//hub (ввод скрыт): '; fi
  [[ $LICENSE_KEY =~ ^[A-Za-z0-9]{16}$ ]] || fail 'Лицензионный ключ должен содержать 16 латинских букв/цифр.'
}
NAMES=('503' 'Первое облако' 'Формат' 'Downloadlify' 'לוי אורבך' 'Лекторий Плюс' 'Omnify' 'Эфир' 'Братский союз' 'Поток')
DESCRIPTIONS=('Страница о временной недоступности сервиса.' 'Сайт корпоративного облачного сервиса.' 'Онлайн-конвертер файлов.' 'Сервис передачи и скачивания больших файлов по ссылке.' 'Сайт бухгалтерских услуг и расчёта зарплаты.' 'Сайт онлайн-лекций и гуманитарных курсов.' 'Сайт музыкальной платформы.' 'Сайт для прослушивания российских радиостанций.' 'Сайт о дружбе России и КНДР.' 'Страница проверки интернет-соединения.')
IDS=('11f33ec1-98d7-418e-8d9b-ce8561a74666' 'a35da056-a58f-4381-baba-8c22cea3faf4' '6d15ae9f-1007-4dc2-a3ee-e7f89c174a23' '3cc55eaa-c231-4974-8668-4f59b2930198' '24238606-9699-4edd-afbf-34410e052ee7' '9332f4b1-f39c-40ab-a544-7e5b6c3c1eb1' '92637c20-8adf-4c12-b44e-c5c4eb7fb498' '4fcc2ae8-c104-4dae-a470-bf3e20be0db7' '22332909-29e9-4d13-b16f-d073d1f1edb9' '8ccaf97c-1ff0-4a9c-8ec0-42c73e8ce88e')
preflight() {
  [[ ! -e $ROOT && ! -e $NODE && ! -e /opt/hysteria && ! -e $NGINX && ! -e $CRON ]] || fail 'Найдены существующие каталоги/конфигурация. Свою установку удалите пунктом 2; чужие данные установщик не перезаписывает.'
  command -v python3 >/dev/null || fail 'Для предварительной проверки нужен python3: apt-get update && apt-get install -y python3 ca-certificates curl'
  command -v curl >/dev/null || fail 'Нужен curl: apt-get install -y curl ca-certificates'
  mapfile -t PANEL_IPS < <(resolve "$PANEL")
  (( ${#PANEL_IPS[@]} )) || fail 'Не удалось разрешить IP панели.'
  mapfile -t DOMAIN_IPS < <(resolve "$DOMAIN")
  (( ${#DOMAIN_IPS[@]} )) || fail 'Домен ноды не разрешается в IP.'
  if command -v ufw >/dev/null; then
    # Дубликат старого правила UFW может остаться ниже нового deny.
    # Не меняем неизвестные правила и не продолжаем с неоднозначным порядком.
    if ufw show added | python3 -c 'import re,sys; port=int(sys.argv[1]); sys.exit(0 if any(int(n)==port for n in re.findall(r"\b[0-9]+\b",sys.stdin.read())) else 1)' "$NODE_PORT"; then
      fail 'В UFW уже есть правило с портом ноды. Удалите/скорректируйте его или выберите другой порт.'
    fi
  fi
  local public4 public6 local_ips ip matched=0
  public4=$(curl -4fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)
  public6=$(curl -6fsS --max-time 8 https://api64.ipify.org 2>/dev/null || true)
  local_ips=$(ip -o addr show | awk '{print $4}' | cut -d/ -f1)
  for ip in "${DOMAIN_IPS[@]}"; do
    if [[ $ip == "$public4" || $ip == "$public6" ]] || [[ $'\n'"$local_ips"$'\n' == *$'\n'"$ip"$'\n'* ]]; then matched=1
    else fail "DNS $DOMAIN содержит $ip, который не найден у этого сервера. Проверьте A/AAAA и отключите CDN-проксирование."
    fi
  done
  (( matched )) || fail 'Не удалось подтвердить DNS ноды.'
  SSH_PORTS=$( { /usr/sbin/sshd -T 2>/dev/null || true; } | awk '$1=="port" {print $2}')
  [[ -z ${SSH_CONNECTION:-} ]] || SSH_PORTS+=$'\n'"${SSH_CONNECTION##* }"
  [[ -n $SSH_PORTS ]] || fail 'Не удалось определить SSH-порт; проверьте sshd -T.'
  for ip in $SSH_PORTS; do [[ $ip != "$NODE_PORT" ]] || fail 'Порт ноды совпадает с SSH-портом.'; done
  [[ -z $(ss -H -ltn "sport = :$NODE_PORT") ]] || fail 'TCP-порт ноды уже занят.'
  [[ -z $(ss -H -lun 'sport = :443') ]] || fail '443/UDP уже занят.'
  local port listeners
  for port in 80 443; do
    listeners=$(ss -H -ltnp "sport = :$port")
    [[ -z $listeners || $listeners == *'"nginx"'* ]] || fail "$port/TCP занят другим веб-сервером."
  done
  if command -v docker >/dev/null && docker container inspect remnanode >/dev/null 2>&1; then fail 'Контейнер remnanode уже существует.'; fi
}
prepare_html() {
  TMP=$(mktemp -d)
  # URL с лицензией передаётся curl через stdin, не попадает в argv или сообщения.
  if ! printf 'url = "https://api.0nehub.xyz/files/k/%s/%s"\n' "$LICENSE_KEY" "${IDS[INDEX]}" |
    curl --config - --proto '=https' --tlsv1.2 --fail --silent --connect-timeout 15 --max-time 120 --max-filesize 20971520 --output "$TMP/index.html"; then
    fail 'Не удалось скачать HTML. Проверьте лицензию и доступность api.0nehub.xyz.'
  fi
  unset LICENSE_KEY ONEHUB_LICENSE_KEY
  customize_html "$TMP/index.html" "$INDEX" "$RANDOMIZE"
}
customize_html() {
  python3 - "$@" <<'PY'
import colorsys,pathlib,re,secrets,sys
p=pathlib.Path(sys.argv[1]); index=int(sys.argv[2]); randomize=int(sys.argv[3])
s=p.read_text(encoding='utf-8-sig')
if not re.search(r'<html\b',s,re.I) or not re.search(r'<title\b',s,re.I) or not re.search(r'</html\s*>',s,re.I):
    sys.exit('Ответ сервера не является полным HTML-макетом.')
if not randomize: sys.exit(0)
palette=secrets.randbelow(10000)
# 10 000 различных поворотов цветового круга, без тождественного поворота.
shift=(palette+1)/10001
def luminance(rgb):
    return sum(w*(c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4) for w,c in zip((.2126,.7152,.0722),rgb))
def rotate(rgb):
    h,l,sat=colorsys.rgb_to_hls(*rgb)
    if sat<.08: return rgb
    target=luminance(rgb); lo=0.; hi=1.
    for _ in range(24):
        mid=(lo+hi)/2
        if luminance(colorsys.hls_to_rgb((h+shift)%1,mid,sat))<target: lo=mid
        else: hi=mid
    return colorsys.hls_to_rgb((h+shift)%1,(lo+hi)/2,sat)
def hex_color(m):
    value=m[1]
    if len(value) in (3,4): value=''.join(c*2 for c in value)
    rgb=tuple(int(value[i:i+2],16)/255 for i in (0,2,4))
    channels=', '.join(f'{c*255:.5f}' for c in rotate(rgb))
    if value[6:]: return 'rgba('+channels+f', {int(value[6:],16)/255:.5f})'
    return 'rgb('+channels+')'
def rgb_color(m):
    rgb=tuple(float(m[i])/255 for i in (2,3,4))
    return m[1]+', '.join(f'{c*255:.5f}' for c in rotate(rgb))+m[5]+')'
def css(value):
    value=re.sub(r'#([a-fA-F0-9]{8}|[a-fA-F0-9]{6}|[a-fA-F0-9]{4}|[a-fA-F0-9]{3})(?![\w-])',hex_color,value)
    # Все десять макетов используют запятые в цветных rgb/rgba.
    return re.sub(r'(rgba?\(\s*)(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)(\s*(?:,\s*[\d.]+)?)\)',rgb_color,value,flags=re.I)
s=re.sub(r'(<style\b[^>]*>)(.*?)(</style\s*>)',lambda m:m[1]+css(m[2])+m[3],s,flags=re.I|re.S)
s=re.sub(r'\b(style|fill|stroke)=("[^"]*"|\x27[^\x27]*\x27)',lambda m:m[1]+'='+m[2][0]+css(m[2][1:-1])+m[2][-1],s,flags=re.I)
p.write_text(s,encoding='utf-8')
print(f'Палитра: {palette+1}/10000')
PY
}
summary() {
  note 'Сводка установки:'
  printf 'Домен: %s\nПорт ноды: %s/TCP\nПанель: %s\n' "$DOMAIN" "$NODE_PORT" "$PANEL"
  printf 'Разрешённые IP панели: %s\n' "${PANEL_IPS[*]}"
  printf 'SECRET_KEY: скрыт\nHTML: %s\nРандомизация палитры: %s\n' "${NAMES[INDEX]}" "$RANDOMIZE"
  printf 'Сайт: 80/TCP и 443/TCP; Hysteria 2: 443/UDP\nСертификат: Let’s Encrypt, автоматическое продление\n'
  printf 'Docker, Remnanode, nginx; UFW будет включён с сохранением доступа по SSH.\n'
  yes 'Продолжить установку?' || { note 'Установка отменена.'; return 1; }
}
write_state() {
  python3 - "$ROOT/state.json" "$DOMAIN" "$NODE_PORT" "$PANEL" "$UFW_WAS_ACTIVE" "$NGINX_WAS_ACTIVE" <<'PY'
import json,pathlib,sys
pathlib.Path(sys.argv[1]).write_text(json.dumps(dict(zip(('domain','port','panel','ufw_active','nginx_active'),sys.argv[2:]))))
PY
}
add_rule() {
  # prepend работает и с пустым ruleset, отдельно для IPv4 и IPv6.
  # insert 1 на пустом списке может завершиться Invalid position '1'.
  ufw prepend "$@"
}

firewall() {
  local ip port
  # Запрет раньше старых общих разрешений; IP панели вставляются перед запретом.
  add_rule deny proto tcp from any to any port "$NODE_PORT" comment onehub-hy2-node-deny
  for ip in "${PANEL_IPS[@]}"; do add_rule allow proto tcp from "$ip" to any port "$NODE_PORT" comment onehub-hy2-panel; done
  for port in $SSH_PORTS; do add_rule allow "$port/tcp" comment onehub-hy2-ssh; done
  add_rule allow 80/tcp comment onehub-hy2-http
  add_rule allow 443/tcp comment onehub-hy2-https
  add_rule allow 443/udp comment onehub-hy2-hysteria
  ufw --force enable
}
install_acme() {
  mkdir -m 700 "$ROOT/acme"
  # Вызываем сам acme.sh: get.acme.sh трактует первый аргумент как email=...
  # и может вернуть 0 даже после неуспешной установки.
  curl --proto '=https' -fsS https://raw.githubusercontent.com/acmesh-official/acme.sh/master/acme.sh -o "$TMP/acme-install.sh"
  if ! (cd "$TMP" && sh "$TMP/acme-install.sh" --install-online --home "$ROOT/acme" --config-home "$ROOT/acme" --nocron --noprofile); then
    fail 'Не удалось установить acme.sh. Проверьте доступ к GitHub.'
  fi
  [[ -s $ROOT/acme/acme.sh ]] || fail 'Установщик acme.sh не создал рабочий файл.'
  "$ROOT/acme/acme.sh" --version >/dev/null || fail 'Установленный acme.sh не запускается.'
}
deploy() {
  section 03 'Развёртывание сервисов'
  mkdir -m 700 "$ROOT"
  UFW_WAS_ACTIVE=0; NGINX_WAS_ACTIVE=0
  if command -v ufw >/dev/null && ufw status | grep -q '^Status: active'; then UFW_WAS_ACTIVE=1; fi
  if systemctl is-active --quiet nginx; then NGINX_WAS_ACTIVE=1; fi
  write_state
  note 'Установка зависимостей…'
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl socat cron nginx ufw openssl python3
  grep -q '^IPV6=yes' /etc/default/ufw || fail 'Для ограничения ноды по IPv6 требуется IPV6=yes в /etc/default/ufw.'
  systemctl enable --now cron
  ufw show added > "$ROOT/ufw-before.txt"
  firewall
  if ! command -v docker >/dev/null; then
    curl --proto '=https' -fsS https://get.docker.com -o "$TMP/docker.sh"
    sh "$TMP/docker.sh"
  fi
  systemctl enable --now docker
  docker compose version >/dev/null || fail 'Docker установлен без Compose plugin. Установите docker-compose-plugin.'
  # Изолированный acme.sh: не меняет ~/.bashrc и не создаёт общий cron.
  install_acme
  "$ROOT/acme/acme.sh" --home "$ROOT/acme" --set-default-ca --server letsencrypt
  mkdir -p "$CERT" "$NODE" "$ROOT/www"
  chmod 700 /opt/hysteria "$CERT" "$NODE"
  install -m 644 "$TMP/index.html" "$ROOT/www/index.html"
  # nginx worker должен читать только web-root, не состояние и секреты.
  chmod 711 "$ROOT"
  chmod 755 "$ROOT/www"
  cat > "$ROOT/acme-pre.sh" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
if systemctl is-active --quiet nginx; then
  touch /opt/onehub-hy2/nginx-was-running
  systemctl stop nginx
fi
HOOK
  cat > "$ROOT/acme-post.sh" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
if [[ -f /opt/onehub-hy2/nginx-was-running ]]; then
  systemctl start nginx
  rm -f /opt/onehub-hy2/nginx-was-running
fi
HOOK
  cat > "$ROOT/reload.sh" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
chmod 600 /opt/hysteria/certs/privkey.pem
# bind-mount каталога подхватывает атомарно заменённые файлы сертификата.
if [[ -f /opt/remnanode/docker-compose.yml ]]; then
  docker compose --project-directory /opt/remnanode -f /opt/remnanode/docker-compose.yml restart remnanode
fi
if systemctl is-active --quiet nginx; then nginx -t && systemctl reload nginx; fi
HOOK
  chmod 700 "$ROOT/"*.sh
  note 'Выпуск сертификата Let’s Encrypt…'
  # Восстановление nginx сработает и при ошибке первоначального выпуска.
  NGINX_STOPPED=1
  "$ROOT/acme/acme.sh" --home "$ROOT/acme" --issue --standalone --keylength ec-256 -d "$DOMAIN" --server letsencrypt \
    --pre-hook "$ROOT/acme-pre.sh" --post-hook "$ROOT/acme-post.sh"
  "$ROOT/acme-post.sh"
  NGINX_STOPPED=0
  "$ROOT/acme/acme.sh" --home "$ROOT/acme" --install-cert -d "$DOMAIN" --ecc \
    --key-file "$CERT/privkey.pem" --fullchain-file "$CERT/fullchain.pem" --reloadcmd "$ROOT/reload.sh"
  write_compose
  write_profile
  write_host_settings
  cat > "$NGINX" <<NG
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    root $ROOT/www;
    index index.html;
    server_tokens off;
    location / { try_files \$uri \$uri/ =404; }
}
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name $DOMAIN;
    ssl_certificate $CERT/fullchain.pem;
    ssl_certificate_key $CERT/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    root $ROOT/www;
    index index.html;
    server_tokens off;
    location / { try_files \$uri \$uri/ =404; }
}
NG
  nginx -t
  systemctl enable --now nginx
  systemctl reload nginx
  cat > "$CRON" <<'CR'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# Ежедневная проверка срока; reload.sh вызывается после реального обновления.
17 3 * * * root flock -n /run/lock/onehub-hy2.lock /opt/onehub-hy2/renew.sh >> /opt/onehub-hy2/renew.log 2>&1
# Дополнительный перезапуск по расписанию пользователя (время сервера).
0 4 1 */2 * root flock -n /run/lock/onehub-hy2.lock /usr/bin/docker compose --project-directory /opt/remnanode -f /opt/remnanode/docker-compose.yml restart remnanode
CR
  chmod 644 "$CRON"
  cat > "$ROOT/renew.sh" <<'RENEW'
#!/usr/bin/env bash
set -euo pipefail
trap '/opt/onehub-hy2/acme-post.sh' EXIT
/opt/onehub-hy2/acme/acme.sh --cron --home /opt/onehub-hy2/acme
RENEW
  chmod 700 "$ROOT/renew.sh"
  docker compose -f "$NODE/docker-compose.yml" pull
  docker compose -f "$NODE/docker-compose.yml" up -d
  sleep 3
  [[ $(docker inspect --format '{{.State.Running}}' remnanode) == true ]] || fail 'Remnanode не запущен.'
  touch "$ROOT/complete"
  unset SECRET_KEY
  show_completion
}
write_host_settings() {
  {
    printf 'Профиль: выберите созданный профиль Hysteria 2\nInbound: HYSTERIA2\n'
    printf 'Адрес: %s\nПорт: 443\nSNI: %s\nTLS: включён\n' "$DOMAIN" "$DOMAIN"
  } > "$ROOT/host-settings.txt"
}
show_completion() {
  section 04 'Установка завершена'
  printf 'Сайт: https://%s\n' "$DOMAIN"
  printf 'Нода в Remnawave: адрес %s, порт API %s/TCP.\n' "$DOMAIN" "$NODE_PORT"
  printf '\nПрофиль конфигурации Remnawave\n'
  printf 'Файл: %s/panel-profile.json\n' "$ROOT"
  printf 'Просмотр: cat %s/panel-profile.json\n' "$ROOT"
  printf 'Создайте профиль в панели, вставьте JSON и назначьте ноде. Пользователей добавляет панель.\n'
  printf '\nНастройки хоста в Remnawave\n'
  cat "$ROOT/host-settings.txt"
  printf 'Файл настроек: %s/host-settings.txt\n' "$ROOT"
  printf '\nОсновные пути файлов\n'
  printf 'Docker Compose: %s/docker-compose.yml\n' "$NODE"
  printf 'HTML сайта: %s/www/index.html\n' "$ROOT"
  printf 'Сертификат: %s/fullchain.pem\nЗакрытый ключ: %s/privkey.pem\n' "$CERT" "$CERT"
  printf 'Конфигурация nginx: %s\n' "$NGINX"
  printf 'Расписание продления: %s\n' "$CRON"
  printf 'Скрипт продления: %s/renew.sh\nЖурнал продления: %s/renew.log\n' "$ROOT" "$ROOT"
}

write_profile() {
  python3 - "$DOMAIN" "$ROOT/panel-profile.json" <<'PROFILE'
import json,pathlib,sys
profile={"inbounds":[{"tag":"HYSTERIA2","listen":"0.0.0.0","port":443,"protocol":"hysteria","settings":{"version":2,"users":[]},"streamSettings":{"network":"hysteria","security":"tls","tlsSettings":{"serverName":sys.argv[1],"alpn":["h3"],"certificates":[{"certificateFile":"/opt/hysteria/certs/fullchain.pem","keyFile":"/opt/hysteria/certs/privkey.pem"}]},"hysteriaSettings":{"version":2,"masquerade":{"type":"file","dir":"/var/www/html"}}}}],"outbounds":[{"protocol":"freedom","tag":"DIRECT"}]}
pathlib.Path(sys.argv[2]).write_text(json.dumps(profile,ensure_ascii=False,indent=2)+"\n")
PROFILE
}

write_compose() {
  # JSON — допустимый YAML. $ удваивается, чтобы Compose не подставлял переменные секрета.
  printf '%s' "$SECRET_KEY" | python3 -c '
import json,sys,pathlib
port=sys.argv[1]; secret=sys.stdin.read().replace("$","$$")
service=dict(container_name="remnanode",hostname="remnanode",image="remnawave/node:latest",network_mode="host",restart="always",cap_add=["NET_ADMIN"],ulimits={"nofile":{"soft":1048576,"hard":1048576}},environment={"NODE_PORT":port,"SECRET_KEY":secret},volumes=["/opt/hysteria/certs:/opt/hysteria/certs:ro","/opt/onehub-hy2/www:/var/www/html:ro"])
pathlib.Path(sys.argv[2]).write_text(json.dumps({"services":{"remnanode":service}},indent=2)+"\n")
' "$NODE_PORT" "$NODE/docker-compose.yml"
  chmod 600 "$NODE/docker-compose.yml"
  docker compose -f "$NODE/docker-compose.yml" config --quiet
}
remove_rules() {
  local -a args=()
  local token
  # show added работает и при выключенном UFW. Не используем eval.
  while IFS= read -r -d '' token; do
    if [[ $token == __ONEHUB_RULE_END__ ]]; then
      ufw "${args[@]}"
      args=()
    else
      args+=("$token")
    fi
  done < <(ufw show added | python3 -c '
import pathlib,shlex,sys
def split(line):
    args=shlex.split(line)
    return args if args and args[0]=="ufw" else []
def identity(args):
    return args[:args.index("comment")] if "comment" in args else args
before=pathlib.Path(sys.argv[1])
original={tuple(identity(a)):a for line in before.read_text().splitlines() if (a:=split(line))} if before.exists() else {}
for line in reversed(sys.stdin.read().splitlines()):
    args=shlex.split(line)
    if not args or args[0]!="ufw" or "comment" not in args: continue
    i=args.index("comment")
    if i+1>=len(args) or not args[i+1].startswith("onehub-hy2-"): continue
    old=original.get(tuple(identity(args)))
    if old:
        # UFW мог заменить comment уже существовавшего правила.
        command=old[1:] if "comment" in old else old[1:]+["comment", ""]
    else: command=["--force","delete"]+args[1:]
    for arg in command+["__ONEHUB_RULE_END__"]: sys.stdout.buffer.write(arg.encode()+b"\0")
' "$ROOT/ufw-before.txt")
}

cleanup() {
  [[ -f $ROOT/state.json ]] || { note 'Изменений этого установщика не найдено.'; return; }
  note 'Будут удалены Remnanode, сайт, сертификаты, cron и правила UFW этого установщика. Docker и системные пакеты останутся.'
  yes 'Удалить изменения установщика?' || return 0
  # При ошибке Docker сначала останавливаемся, сохраняя всё для повторной попытки.
  if [[ -f $NODE/docker-compose.yml ]]; then docker compose -f "$NODE/docker-compose.yml" down; fi
  rm -f "$CRON" "$NGINX"
  if command -v nginx >/dev/null; then nginx -t; systemctl reload nginx || true; fi
  if command -v ufw >/dev/null; then
    remove_rules
    if [[ $(state ufw_active) == 0 ]]; then ufw --force disable; fi
  fi
  if [[ $(state nginx_active) == 0 ]]; then systemctl stop nginx; fi
  rm -rf -- "$NODE" /opt/hysteria "$ROOT"
  note 'Изменения установщика удалены. Остальные контейнеры, пакеты и правила сохранены.'
}
state() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$ROOT/state.json" "$1"; }
diagnostics() {
  section '•' 'Диагностика'
  printf 'ОС: '; cat /etc/debian_version
  for service in docker nginx cron; do printf '%s: ' "$service"; systemctl is-active "$service" || true; done
  if command -v docker >/dev/null; then
    docker --version
    docker compose version || true
    docker ps -a --filter name='^/remnanode$' --format 'Контейнер: {{.Names}} | {{.Status}} | {{.Image}}' || true
  fi
  # Не выводим docker inspect/config/logs: там могут оказаться секреты.
  if command -v ufw >/dev/null; then ufw status numbered; fi
  printf '\nПрослушиваемые TCP/UDP-порты:\n'; ss -lntu
  if [[ -f $ROOT/state.json ]]; then
    local domain; domain=$(state domain)
    printf '\nDNS %s:\n' "$domain"; resolve "$domain" || true
    if [[ -f $CERT/fullchain.pem ]]; then openssl x509 -in "$CERT/fullchain.pem" -noout -subject -issuer -dates; fi
    if [[ -f $ROOT/complete ]]; then note 'Установка завершена.'; else note 'Установка не была завершена; доступна очистка пунктом 2.'; fi
    printf 'Cron продления: '; if [[ -f $CRON ]]; then echo 'настроен'; else echo 'не настроен'; fi
    if command -v curl >/dev/null; then curl --silent --show-error --max-time 10 -o /dev/null -w 'HTTPS: %{http_code}\n' "https://$domain" || true; fi
  fi
}
main() {
  [[ ${BASH_VERSINFO[0]} -ge 4 ]] || fail 'Требуется Bash 4 или новее.'
  require_system
  local action
  while :; do
    banner
    printf '1) Начать установку\n2) Очистить сервер (удалить изменения установщика)\n3) Диагностика\n\n0) Выход\n\n'
    ask action 'Ваш выбор: '
    case $action in
      1) collect; preflight; prepare_html; if summary; then deploy; fi ;;
      2) cleanup ;;
      3) diagnostics ;;
      0) return 0 ;;
      *) note 'Выберите 0, 1, 2 или 3.'; continue ;;
    esac
    ask action 'Нажмите Enter для возврата в меню…'
  done
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
