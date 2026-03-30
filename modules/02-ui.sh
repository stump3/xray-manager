# ──────────────────────────────────────────────────────────────────────────────
#  ВСПОМОГАТЕЛЬНЫЕ UI-ФУНКЦИИ
# ──────────────────────────────────────────────────────────────────────────────

tw() { tput cols 2>/dev/null || echo 80; }

cls() { printf "\e[2J\e[H"; }

# 🔧 БАГ 5 FIX: подсчитать видимую ширину текста с учётом эмодзи (занимают 2 колонки)
# Usage: local width=$(visible_width "my 🚀 text"); echo $width
visible_width() {
    local text="$1"
    # Убрать ANSI escape-коды
    local clean; clean=$(printf "%b" "$text" | sed 's/\x1b\[[0-9;]*m//g')
    # Используем python3 для точного подсчёта визуальных колонок.
    # east_asian_width W/F = wide (2 колонки): все эмодзи, CJK и т.д.
    # Это правильно обрабатывает любые символы, не только жёстко перечисленные.
    python3 -c "
import unicodedata, sys
s = sys.argv[1]
print(sum(2 if unicodedata.east_asian_width(c) in ('W','F') else 1 for c in s))
" "$clean" 2>/dev/null && return
    # Fallback если python3 недоступен: bash ${#} (без учёта wide chars)
    echo "${#clean}"
}

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
    
    # 🔧 БАГ 5 FIX: считать видимую ширину включая эмодзи
    local raw_lb; raw_lb=$(printf "%b" "$lb" | sed 's/\x1b\[[0-9;]*m//g')
    local vis_lb=$(visible_width "$raw_lb")
    local vis_ic=$(visible_width "$ic")
    
    # Стрипаем ANSI из badge для корректного расчёта ширины
    local raw_badge; raw_badge=$(printf "%b" "$badge" | sed 's/\x1b\[[0-9;]*m//g')
    
    # ${#n} = 1, эмодзи иконка = vis_ic (с учётом что занимает 2 колонки), 8 = "│  N)  "
    local used=$(( ${#n} + vis_ic + vis_lb + 8 ))
    local pad=$(( i - used - ${#raw_badge} - 1 ))
    [[ $pad -lt 0 ]] && pad=0
    if [[ -n "$badge" ]]; then
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

