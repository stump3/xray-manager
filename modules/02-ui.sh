# ──────────────────────────────────────────────────────────────────────────────
#  ВСПОМОГАТЕЛЬНЫЕ UI-ФУНКЦИИ
# ──────────────────────────────────────────────────────────────────────────────

tw() { tput cols 2>/dev/null || echo 80; }

cls() { printf "\e[2J\e[H"; }

box_top() {
    local title="$1" col="${2:-$CYAN}"
    local w; w=$(tw); local i=$((w-2))
    local tl=${#title}; local p=$(( (i - tl - 2) ))
    local pl=$(( p/2 )); local pr=$(( p - pl ))
    printf "${DIM}╭%s╮${R}\n" "$(printf '%*s' "$i" | tr ' ' '─')"
    printf "${DIM}│${R} ${col}${BOLD}%*s%s%*s${R} ${DIM}│${R}\n" "$pl" "" "$title" "$pr" ""
    printf "${DIM}├%s┤${R}\n" "$(printf '%*s' "$i" | tr ' ' '─')"
}

box_end() {
    local w; w=$(tw); local i=$((w-2))
    printf "${DIM}╰%s╯${R}\n" "$(printf '%*s' "$i" | tr ' ' '─')"
}

box_mid() {
    local w; w=$(tw); local i=$((w-2))
    printf "${DIM}├%s┤${R}\n" "$(printf '%*s' "$i" | tr ' ' '─')"
}

box_row() {
    local text="$1"
    local w; w=$(tw); local i=$((w-2))
    local raw; raw=$(printf "%b" "$text" | sed 's/\x1b\[[0-9;]*m//g')
    local rl=${#raw}; local pad=$((i - rl - 2))
    [[ $pad -lt 0 ]] && pad=0
    printf "${DIM}│${R} %b%*s${DIM}│${R}\n" "$text" "$pad" ""
}

box_blank() {
    local w; w=$(tw); local i=$((w-2))
    printf "${DIM}│%*s│${R}\n" "$i" ""
}

mi() {
    # menu_item num icon label [badge]
    local n="$1" ic="$2" lb="$3" badge="${4:-}"
    local w; w=$(tw); local i=$((w-2))
    local raw_lb; raw_lb=$(printf "%b" "$lb" | sed 's/\x1b\[[0-9;]*m//g')
    # Стрипаем ANSI из badge для корректного расчёта ширины
    local raw_badge; raw_badge=$(printf "%b" "$badge" | sed 's/\x1b\[[0-9;]*m//g')
    local used=$(( ${#n} + ${#raw_lb} + 8 ))
    local pad=$(( i - used - ${#raw_badge} - 1 ))
    [[ $pad -lt 0 ]] && pad=0
    if [[ -n "$badge" ]]; then
        # %b интерпретирует \e escape-коды в badge (статусы MTProto/Hysteria2)
        printf "${DIM}│${R}  ${YELLOW}${BOLD}%s)${R} %s %b%*s${DIM}%b │${R}\n" \
            "$n" "$ic" "$lb" "$pad" "" "$badge"
    else
        printf "${DIM}│${R}  ${YELLOW}${BOLD}%s)${R} %s %b%*s${DIM}│${R}\n" \
            "$n" "$ic" "$lb" "$pad" ""
    fi
}

ask() {
    local label="$1" var="$2" def="${3:-}"
    if [[ -n "$def" ]]; then
        printf "${DIM}│${R} ${CYAN}?${R} ${LIGHT}%s${R} ${DIM}[%s]${R}: " "$label" "$def"
    else
        printf "${DIM}│${R} ${CYAN}?${R} ${LIGHT}%s${R}: " "$label"
    fi
    local inp; read -r inp
    [[ -z "$inp" && -n "$def" ]] && inp="$def"
    printf -v "$var" '%s' "$inp"
}

confirm() {
    local msg="$1" def="${2:-n}"
    local pr="[y/N]"; [[ "$def" == "y" ]] && pr="[Y/n]"
    printf "${YELLOW}?${R} %s %s: " "$msg" "$pr"
    local a; read -r a; a="${a:-$def}"
    [[ "$a" =~ ^[Yy]$ ]]
}

pause() {
    printf "\n${DIM}%s${R}" "${1:-Нажмите Enter...}"
    read -r
}

ok()   { printf " ${GREEN}✓${R} %b\n" "$*"; }
err()  { printf " ${RED}✗${R} ${RED}%b${R}\n" "$*"; }
warn() { printf " ${YELLOW}⚠${R} %b\n" "$*"; }
info() { printf " ${BLUE}ℹ${R} %b\n" "$*"; }

spin_start() {
    printf "\r${CYAN}⠋${R} %s..." "$1"
    ( local f=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏") i=0
      while true; do
          printf "\r${CYAN}%s${R} %s..." "${f[$((i%10))]}" "$1"
          sleep 0.08; ((i++))
      done ) &
    _SPIN=$!
}
spin_stop() {
    [[ -n "${_SPIN:-}" ]] && { kill "$_SPIN" 2>/dev/null; wait "$_SPIN" 2>/dev/null || true; _SPIN=""; }
    if [[ "${1:-ok}" == "ok" ]]; then printf "\r${GREEN}✓${R} Готово!%-25s\n" ""
    else printf "\r${RED}✗${R} Ошибка!%-25s\n" ""; fi
}

hr() {
    local w; w=$(tw)
    printf "${DIM}%s${R}\n" "$(printf '%*s' "$w" | tr ' ' '─')"
}

