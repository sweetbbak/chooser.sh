#!/usr/bin/env bash
# set -x

# Resources:
#   https://espterm.github.io/docs/VT100%20escape%20codes.html
#   https://github.com/wick3dr0se/bashin/blob/main/lib/std/ansi.sh
#   https://github.com/wick3dr0se/bashin/blob/main/lib/std/tui.sh
#   https://github.com/wick3dr0se/fml/blob/main/fml
#   https://invisible-island.net/xterm/ctlseqs/ctlseqs.html
#   https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797
#   https://stackoverflow.com/questions/2612274/bash-shell-scripting-detect-the-enter-key

shopt -s checkwinsize; (:;:)
# printf '\e[?1000h'  # enable mouse support

usage() { printf 'Usage: %s [choices...]\n' "${0##*/}"; exit 0; }
cursor_up(){ printf '\e[A'; }
cursor_down(){ printf '\e[B'; }
# cursor_up(){ printf "\e[A\e[48;5;105m%s\e[0m" "░" ; }
# cursor_down(){ printf "\e[B\e[48;5;105m%s\e[0m" "░" ; }
# cursor_up(){ printf "\e[A\e[48;5;105m%s\e[0m" ">" ; }
# cursor_down(){ printf "\e[B\e[48;5;105m%s\e[0m" ">" ; }
cursor_save(){ printf '\e7'; }
cursor_restore(){ printf '\e8'; }
# read_keys(){ read -rsn1 KEY </dev/tty; }
read_keys(){
    unset K1 K2 K3
    # shellcheck disable=2162
    read -sN1 </dev/tty
    K1="$REPLY"
    # shellcheck disable=2162
    read -sN2 -t 0.001 </dev/tty
    K2="$REPLY"
    # shellcheck disable=2162
    read -sN1 -t 0.001 </dev/tty
    K3="$REPLY"
    # this will read full keysets like 'enter' and 'space' instead of just j or k
    KEY="$K1$K2$K3"
}
set_offset() { IFS='[;' read -p $'\e[6n' -d R -rs _ offset _ _ </dev/tty; }
cleanup() {
    printf '\e[%d;1H' "$offset"
    for ((i=0;i<=ROWS;i++));do printf '\e[2K'; cursor_down ;done
    printf '\e[%d;1H' "$offset"
    stty echo </dev/tty
    tput cnorm
    exec 1>&3 3>&-  # restore stdout and close fd #3
    # [ -n "$sel" ] && printf '%s\n' "$sel"
    [ -n "$sel" ] && printf '%s\n' "${sel[@]}"
}
list_choices() {
    printf '\e[%d;1H' "$offset"  # go back to the start position
    printf ' %-80s│\n' "${choices[@]:pos:$ROWS}"
    printf '\e[%d;1H>' "$cursor"  # go back to the cursor position
}

[ -z "$1" ] && usage

declare -a choices=()
if [ "$1" = - ];then
    while read -r i; do choices+=("$i"); done
else 
    choices=("$@")
fi

exec 3>&1  # send stdout to fd 3
exec >&2   # send stdout to stderr
stty -echo </dev/tty
tput civis
pos=0
total_choices=${#choices[@]}
((ROWS = (LINES / 2) + 1))
set_offset
if (( (offset + ROWS) > LINES )) && (( total_choices >= ROWS ));then # TODO: don't do this?
    printf '\e[%d;1H' "$((offset - ROWS + 1))";
    set_offset
fi
cursor=$offset

declare -a multiple_choice
multiple_choice=()

cursor_up_logic() {
    if (( cursor == offset )) && (( pos > 0 ));then
        ((pos-=1))
    elif (( cursor > offset ));then
        ((cursor-=1))
        cursor_up
    fi
}

cursor_down_logic() {

    (( actual_pos == (total_choices - 1) )) && return # TODO: fix this, unecessary logic?
    if (( cursor == (ROWS + offset - 1) )) && (( (total_choices - pos) != ROWS ))
    then
        ((pos+=1))
    elif (( cursor < (ROWS + offset - 1) ))
    then
        ((cursor+=1))
        cursor_down
    fi
}

add_multiple() {
    if [[ "${multiple_choice[*]}" =~ ${1} ]]; then
        cursor_down_logic
        return
    else
        multiple_choice+=("${choices[actual_pos]}")
        cursor_down_logic
    fi
}

enter() {
    # if [[ "${choices[actual_pos]}" =~ ${multiple_choice[*]} ]]; then
    if [[  ${multiple_choice[*]} =~ ${choices[actual_pos]} ]]; then
        sel="${multiple_choice[*]}" ; exit 0
    else
        sel="${choices[actual_pos]} ${multiple_choice[*]}"
    fi
    exit 0
    
}

(( (total_choices - pos) >= ROWS )) && printf '\e[%d;1H▼' "$((ROWS + offset))"
trap cleanup EXIT
while :;do
    ((actual_pos = cursor - offset + pos)) || true
    list_choices
    read_keys
    # fixes exiting when holding down keys
    sleep 0.0001
    case "${KEY}" in
        k|$'\x1b\x5b\x41') cursor_up_logic ;;
        j|$'\x1b\x5b\x42') cursor_down_logic ;;
        $'\x1b') exit 0 ;; # ESC key
        $'\x09') add_multiple "${choices[actual_pos]}" ;; # TAB key
        $'\n'|$'\x0a') enter ;;
    esac
done
