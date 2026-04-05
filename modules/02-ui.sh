# ──────────────────────────────────────────────────────────────────────────────
#  UI — минималистичный стиль
# ──────────────────────────────────────────────────────────────────────────────
# shellcheck disable=SC2059

tw() { tput cols 2>/dev/null || echo 80; }

cls() { printf "\e[2J\e[H"; }

# Видимая ширина строки с учётом emoji и ANSI-кодов
visible_width() {
    local text="$1"
    local clean; clean=$(printf "%b" "$text" | sed 's/\x1b\[[0-9;]*m//g')
    python3 -c "
import unicodedata, sys
s = sys.argv[1]; w = 0
for c in s:
    cp = ord(c)
    if cp == 0xFE0F: continue
    ew = unicodedata.east_asian_width(c)
    if ew in ('W','F'):                                      w += 2; continue
    if 0x1F000 <= cp <= 0x1FFFF:                             w += 2; continue
    if unicodedata.category(c) == 'So' and 0x2600 <= cp <= 0x27FF: w += 2; continue
    w += 1
print(w)
" "$clean" 2>/dev/null && return
    echo "${#clean}"
}

# ── Разделитель ────────────────────────────────────────────────────────────────

_sep() {
    local w; w=$(tw)
    printf "${DIM}%s${R}\n" "$(printf '%*s' "$w" "" | tr ' ' '─')"
}

# ── Компоненты секции ──────────────────────────────────────────────────────────

box_top() {
    local title="$1" col="${2:-$CYAN}"
    printf "\n"
    _sep
    printf "  ${col}${BOLD}%s${R}\n" "$title"
    _sep
}

box_end() {
    _sep
    printf "\n"
}

box_mid() {
    printf "\n"
    _sep
}

box_row() {
    printf "  %b\n" "$1"
}

box_blank() {
    printf "\n"
}

# ── Пункт меню ─────────────────────────────────────────────────────────────────
mi() {
    local n="$1" ic="$2" lb="$3" badge="${4:-}"
    local w; w=$(tw)

    local raw_lb; raw_lb=$(printf "%b" "$lb" | sed 's/\x1b\[[0-9;]*m//g')
    local raw_badge; raw_badge=$(printf "%b" "$badge" | sed 's/\x1b\[[0-9;]*m//g')
    local vis_ic; vis_ic=$(visible_width "$ic")
    local vis_lb; vis_lb=$(visible_width "$raw_lb")
    local base=$(( 5 + ${#n} + vis_ic + vis_lb ))
    local pad

    if [[ -n "$badge" ]]; then
        pad=$(( w - base - ${#raw_badge} - 2 ))
        [[ $pad -lt 1 ]] && pad=1
        printf "  ${CYAN}%s${R}  %s %b%*s${DIM}%b${R}\n" \
            "$n" "$ic" "$lb" "$pad" "" "$badge"
    else
        printf "  ${CYAN}%s${R}  %s %b\n" "$n" "$ic" "$lb"
    fi
}

# ── Ввод ───────────────────────────────────────────────────────────────────────

ask() {
    local label="$1" var="$2" def="${3:-}"
    if [[ -n "$def" ]]; then
        printf "  ${CYAN}?${R}  ${LIGHT}%s${R} ${DIM}[%s]${R}  " "$label" "$def"
    else
        printf "  ${CYAN}?${R}  ${LIGHT}%s${R}  " "$label"
    fi
    read -r -t 0.01 _flush 2>/dev/null || true
    local inp; read -r inp
    inp=$(printf '%s' "$inp" | tr -d '[:cntrl:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [[ -z "$inp" && -n "$def" ]] && inp="$def"
    printf -v "$var" '%s' "$inp"
}

confirm() {
    local msg="$1" def="${2:-n}"
    local pr="[y/N]"; [[ "$def" == "y" ]] && pr="[Y/n]"
    printf "  ${YELLOW}?${R}  %s %s  " "$msg" "$pr"
    local a; read -r a; a="${a:-$def}"
    [[ "$a" =~ ^[Yy]$ ]]
}

pause() {
    printf "\n  ${DIM}%s${R}" "${1:-Нажмите Enter...}"
    read -r
    printf "\n"
}

confirm_word() {
    local phrase="${1:-ПОДТВЕРДИТЬ}" _w
    printf "  ${RED}Введите ${BOLD}%s${R}${RED} для продолжения:${R}  " "$phrase"
    read -r _w < /dev/tty
    [[ "$_w" == "$phrase" ]]
}

# ── Статус-бар ─────────────────────────────────────────────────────────────────
render_status_bar() {
    local xray="${1:-${DIM}?${R}}" ngx="${2:-${DIM}?${R}}" \
          sub="${3:-${DIM}?${R}}" ip="${4:-?}"
    printf "  xray %b   nginx %b   sub %b   ${DIM}%s${R}\n" \
        "$xray" "$ngx" "$sub" "$ip"
}

# ── Уведомления ────────────────────────────────────────────────────────────────

ok()   { printf "  ${GREEN}✓${R}  %b\n" "$*"; }
err()  { printf "  ${RED}✗${R}  ${RED}%b${R}\n" "$*"; }
warn() { printf "  ${YELLOW}!${R}  %b\n" "$*"; }
info() { printf "  ${DIM}→${R}  %b\n" "$*"; }

# ── Спиннер ────────────────────────────────────────────────────────────────────

spin_start() {
    printf "\r  ${CYAN}⠋${R}  %s..." "$1"
    ( local f=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏") i=0
      while true; do
          printf "\r  ${CYAN}%s${R}  %s..." "${f[$((i%10))]}" "$1"
          sleep 0.08; (( i++ )) || true
      done ) &
    _SPIN=$!
}

spin_stop() {
    [[ -n "${_SPIN:-}" ]] && { kill "$_SPIN" 2>/dev/null; wait "$_SPIN" 2>/dev/null || true; _SPIN=""; }
    if [[ "${1:-ok}" == "ok" ]]; then printf "\r  ${GREEN}✓${R}  Готово!%-30s\n" ""
    else printf "\r  ${RED}✗${R}  Ошибка!%-30s\n" ""; fi
}

hr() { _sep; }
