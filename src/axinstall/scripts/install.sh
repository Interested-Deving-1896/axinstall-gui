#!/usr/bin/bash
set -uo pipefail

logfile="/tmp/axinstall-output.txt"

log() {
    local level="$1"; shift
    local color reset
    case "$level" in
        INFO)  color='\e[36m' ;;
        WARN)  color='\e[33m' ;;
        ERROR) color='\e[31m' ;;
        *)     color='\e[0m'  ;;
    esac
    reset='\e[0m'
    message="[$level] $*"

    # printing to term
    echo -e "${color}${message}${reset}"

    # printing to logfile
    echo "$message" >> "$logfile"
}

run() {
    "$@" | tee -a "$logfile"
    local status=${PIPESTATUS[0]}
    if [ $status -ne 0 ]; then
        log ERROR "Command failed: $*"
        exit $status
    fi
}

log INFO "Running reflector to sort for fastest mirrors"

mirror_region=$(jq -r '.mirrors.region' ~/.config/axinstall.json)

if ! sudo reflector \
    --country "$mirror_region,Singapore,France,Germany" \
    --protocol https \
    --latest 15 \
    --age 6 \
    --sort rate \
    --save /etc/pacman.d/mirrorlist | tee -a "$logfile"; then
    
    log WARN "Reflector localized search failed. Falling back to global Tier-1 mirrors."
    sudo reflector --protocol https --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
fi

# Let's fix pacman's impatience while we're at it
log INFO "Tuning pacman for high-latency connections"
sudo sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf

# This adds a 60s timeout to XferCommand because the default is too 'quit-heavy'
if ! grep -q "XferCommand" /etc/pacman.conf; then
    echo 'XferCommand = /usr/bin/curl -L -C - -f -s %u -o %o --connect-timeout 60 --retry 3' | sudo tee -a /etc/pacman.conf
fi

set -e # Now we can exit because now we are moving to critical stuff

log INFO "Initializing pacman keyring"
run sudo pacman-key --init
run sudo pacman-key --populate archlinux

log INFO "Starting installation"
run sudo axinstall-cli config ~/.config/axinstall.json
