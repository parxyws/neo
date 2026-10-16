#!/usr/bin/env bash
# shellcheck shell=bash
# Inline terminal picker for Neo — interactive arrow-key selection in pure Bash.
# Zero external dependencies (no whiptail or newt needed). With --yes, calls return defaults.

ui_init() {
  # Trap cursor restoration on interrupt
  trap 'printf "\033[?25h" >&2' EXIT INT TERM
}

_read_key() {
  local tty_in=${1:-/dev/tty}
  local key rest
  IFS= read -rsn1 key <"$tty_in" 2>/dev/null || IFS= read -rsn1 key || true
  if [[ $key == $'\033' ]]; then
    read -rsn2 -t0.1 rest <"$tty_in" 2>/dev/null || read -rsn2 -t0.1 rest || true
    key+="$rest"
  fi
  printf '%s' "$key"
}

# ui_msg <title> <text>
ui_msg() {
  if (( ASSUME_YES )); then log_info "$2"; return 0; fi
  local tty_in=/dev/tty
  [[ -r /dev/tty ]] || tty_in=/dev/stdin

  printf '\n\033[1;36m╭─ \033[1;37m%s\033[1;36m %s\033[0m\n' "$1" "$(printf '─%.0s' {1..35})" >&2
  while IFS= read -r line; do
    printf '\033[1;36m│\033[0m %s\n' "$line" >&2
  done <<<"$2"
  printf '\033[1;36m╰%s\033[0m\n' "$(printf '─%.0s' {1..45})" >&2
  printf '\033[2m  Press Enter to continue...\033[0m' >&2
  local dummy
  IFS= read -rs dummy <"$tty_in" 2>/dev/null || true
  printf '\n' >&2
}

# ui_scroll <title> <text>
ui_scroll() {
  ui_msg "$1" "$2"
}

# ui_yesno <title> <text> [yes|no]
ui_yesno() {
  local title=$1 text=$2 def=${3:-yes}
  if (( ASSUME_YES )); then [[ $def == yes ]]; return; fi

  local cur=0
  [[ $def == no ]] && cur=1

  local tty_in=/dev/tty
  [[ -r /dev/tty ]] || tty_in=/dev/stdin

  printf '\n\033[1;36m? \033[1m%s\033[0m' "$title" >&2
  [[ -n $text ]] && printf '\n\033[2m%s\033[0m\n' "$text" >&2 || printf '\n' >&2

  printf '\033[?25l' >&2
  local first=1

  while true; do
    if (( ! first )); then
      printf '\033[2A' >&2
    fi
    first=0

    if (( cur == 0 )); then
      printf '\033[2K\033[1;36m  ▸ \033[1;32mYes\033[0m\n\033[2K    \033[2mNo\033[0m\n' >&2
    else
      printf '\033[2K    \033[2mYes\033[0m\n\033[2K\033[1;36m  ▸ \033[1;31mNo\033[0m\n' >&2
    fi

    local key
    key=$(_read_key "$tty_in")

    case "$key" in
      $'\033[A'|$'\033[B'|$'\033OA'|$'\033OB'|$'\033[C'|$'\033[D'|j|k|h|l)
        cur=$(( 1 - cur ))
        ;;
      y|Y)
        cur=0
        ;;
      n|N)
        cur=1
        ;;
      ""|$'\n'|$'\r')
        printf '\033[?25h' >&2
        if (( cur == 0 )); then
          printf '\033[2K\033[1;32m✓ \033[1m%s\033[0m: \033[1;32mYes\033[0m\n' "$title" >&2
          return 0
        else
          printf '\033[2K\033[1;33m! \033[1m%s\033[0m: \033[1;31mNo\033[0m\n' "$title" >&2
          return 1
        fi
        ;;
      q|Q|$'\x03')
        printf '\033[?25h\n' >&2
        return 130
        ;;
    esac
  done
}

# ui_input <title> <text> <default>
ui_input() {
  local title=$1 text=$2 default=${3:-}
  if (( ASSUME_YES )); then printf '%s' "$default"; return 0; fi

  local tty_in=/dev/tty
  [[ -r /dev/tty ]] || tty_in=/dev/stdin

  printf '\n\033[1;36m? \033[1m%s\033[0m' "$title" >&2
  if [[ -n $default ]]; then
    printf ' \033[2m(%s)\033[0m\n  \033[2mDefault: [%s]\033[0m\n  > ' "$text" "$default" >&2
  else
    printf ' \033[2m— %s\033[0m\n  > ' "$text" >&2
  fi

  local val
  IFS= read -r val <"$tty_in" || true
  val=${val:-$default}
  printf '%s' "$val"
}

# ui_password <title> <text>
ui_password() {
  local title=$1 text=$2
  if (( ASSUME_YES )); then return 1; fi

  local tty_in=/dev/tty
  [[ -r /dev/tty ]] || tty_in=/dev/stdin

  printf '\n\033[1;36m? \033[1m%s\033[0m \033[2m(%s)\033[0m\n  > ' "$title" "$text" >&2
  local val
  IFS= read -rs val <"$tty_in" || true
  printf '\n' >&2
  printf '%s' "$val"
}

# ui_menu <title> <text> <default> <tag> <label> ...
ui_menu() {
  local title=$1 text=$2 default=$3
  shift 3

  if (( ASSUME_YES )); then printf '%s' "$default"; return 0; fi

  local -a tags=() labels=()
  local i def_idx=0 idx=0
  while (( $# >= 2 )); do
    tags+=("$1")
    labels+=("$2")
    if [[ $1 == "$default" ]]; then def_idx=$idx; fi
    idx=$((idx + 1))
    shift 2
  done

  local total=${#tags[@]}
  (( total == 0 )) && return 1

  local cur=$def_idx
  local tty_in=/dev/tty
  [[ -r /dev/tty ]] || tty_in=/dev/stdin

  printf '\n\033[1;36m? \033[1m%s\033[0m' "$title" >&2
  [[ -n $text ]] && printf ' \033[2m— %s\033[0m' "$text" >&2
  printf '\n\033[2m  (Use arrow keys, Enter to select, q to quit)\033[0m\n' >&2

  printf '\033[?25l' >&2
  local first=1

  while true; do
    if (( ! first )); then
      printf '\033[%dA' "$total" >&2
    fi
    first=0

    for ((i = 0; i < total; i++)); do
      if (( i == cur )); then
        printf '\033[2K\033[1;36m  ▸ \033[1;37m%s\033[0m\n' "${labels[i]}" >&2
      else
        printf '\033[2K\033[2m    %s\033[0m\n' "${labels[i]}" >&2
      fi
    done

    local key
    key=$(_read_key "$tty_in")

    case "$key" in
      $'\033[A'|$'\033OA'|k|K)
        (( cur > 0 )) && cur=$((cur - 1)) || cur=$((total - 1))
        ;;
      $'\033[B'|$'\033OB'|j|J)
        (( cur < total - 1 )) && cur=$((cur + 1)) || cur=0
        ;;
      ""|$'\n'|$'\r')
        printf '\033[?25h' >&2
        printf '\033[2K\033[1;32m✓ \033[1m%s\033[0m: \033[1;36m%s\033[0m\n' "$title" "${labels[cur]}" >&2
        printf '%s' "${tags[cur]}"
        return 0
        ;;
      q|Q|$'\x03')
        printf '\033[?25h\n' >&2
        return 130
        ;;
    esac
  done
}

# ui_checklist <title> <text> <tag> <label> <on|off> ...
ui_checklist() {
  local title=$1 text=$2
  shift 2

  if (( ASSUME_YES )); then
    while (( $# >= 3 )); do
      [[ $3 == on ]] && printf '%s\n' "$1"
      shift 3
    done
    return 0
  fi

  local -a tags=() labels=() states=()
  while (( $# >= 3 )); do
    tags+=("$1")
    labels+=("$2")
    states+=("$3")
    shift 3
  done

  local total=${#tags[@]}
  (( total == 0 )) && return 0

  local cur=0 i
  local tty_in=/dev/tty
  [[ -r /dev/tty ]] || tty_in=/dev/stdin

  printf '\n\033[1;36m? \033[1m%s\033[0m' "$title" >&2
  [[ -n $text ]] && printf ' \033[2m— %s\033[0m' "$text" >&2
  printf '\n\033[2m  (Space to toggle, Enter to confirm, a to toggle all, q to quit)\033[0m\n' >&2

  printf '\033[?25l' >&2
  local first=1

  while true; do
    if (( ! first )); then
      printf '\033[%dA' "$total" >&2
    fi
    first=0

    for ((i = 0; i < total; i++)); do
      local box
      if [[ ${states[i]} == on ]]; then
        box="\033[1;32m[✓]\033[0m"
      else
        box="\033[2m[ ]\033[0m"
      fi

      if (( i == cur )); then
        printf '\033[2K\033[1;36m  ▸ %b \033[1;37m%s\033[0m\n' "$box" "${labels[i]}" >&2
      else
        printf '\033[2K    %b \033[2m%s\033[0m\n' "$box" "${labels[i]}" >&2
      fi
    done

    local key
    key=$(_read_key "$tty_in")

    case "$key" in
      $'\033[A'|$'\033OA'|k|K)
        (( cur > 0 )) && cur=$((cur - 1)) || cur=$((total - 1))
        ;;
      $'\033[B'|$'\033OB'|j|J)
        (( cur < total - 1 )) && cur=$((cur + 1)) || cur=0
        ;;
      " ")
        if [[ ${states[cur]} == on ]]; then
          states[cur]=off
        else
          states[cur]=on
        fi
        ;;
      a|A)
        local any_on=0
        for ((i = 0; i < total; i++)); do [[ ${states[i]} == on ]] && any_on=1; done
        for ((i = 0; i < total; i++)); do
          if (( any_on )); then states[i]=off; else states[i]=on; fi
        done
        ;;
      ""|$'\n'|$'\r')
        printf '\033[?25h' >&2
        local -a chosen=()
        for ((i = 0; i < total; i++)); do
          if [[ ${states[i]} == on ]]; then
            chosen+=("${tags[i]}")
          fi
        done
        printf '\033[2K\033[1;32m✓ \033[1m%s\033[0m: \033[1;36m%d selected\033[0m\n' "$title" "${#chosen[@]}" >&2
        for t in "${chosen[@]}"; do
          printf '%s\n' "$t"
        done
        return 0
        ;;
      q|Q|$'\x03')
        printf '\033[?25h\n' >&2
        return 130
        ;;
    esac
  done
}
