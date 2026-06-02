#!/bin/bash
# Ensures that dependencies are installed and corrects them if that is not the case.

if [[ $(_os_distro) == "ubuntu" ]]; then
    # Enable universe/multiverse/restricted before any package installs so that
    # software-properties-common (which may live in universe) is reachable.
    listFile="/etc/apt/sources.list.d/ubuntu.sources"
    if [[ -f ${listFile} ]]; then
        components=(universe multiverse restricted)
        tmpFile=$(mktemp)
        cp "$listFile" "$tmpFile"
        for component in "${components[@]}"; do
            sed -i "/^Components:/ {
                /$component/! s/$/ $component/
            }" "$tmpFile"
        done

        if ! cmp -s "$listFile" "$tmpFile"; then
            if mv "$tmpFile" "$listFile"; then
                trigger_apt_update=true
            else
                rm -f "$tmpFile"
                echo_error "Failed to update $listFile"
                exit 1
            fi
        else
            rm "$tmpFile"
        fi
    else
        # Legacy sources.list – use sed so we don't need add-apt-repository yet.
        components=(universe multiverse restricted)
        tmpFile=$(mktemp)
        cp /etc/apt/sources.list "$tmpFile"
        chmod --reference=/etc/apt/sources.list "$tmpFile"
        chown --reference=/etc/apt/sources.list "$tmpFile"
        for component in "${components[@]}"; do
            sed -i "/^[[:space:]]*#/! /^deb[[:space:]]/ {
                /$component/! s/$/ $component/
            }" "$tmpFile"
        done
        if ! cmp -s /etc/apt/sources.list "$tmpFile"; then
            if mv "$tmpFile" /etc/apt/sources.list; then
                trigger_apt_update=true
            else
                rm -f "$tmpFile"
                echo_error "Failed to update /etc/apt/sources.list"
                exit 1
            fi
        else
            rm "$tmpFile"
        fi
    fi
elif [[ $(_os_distro) == "debian" ]]; then
    listFile="/etc/apt/sources.list.d/debian.sources"
    if [[ -f ${listFile} ]]; then
        components=(contrib non-free)
        tmpFile=$(mktemp)
        cp "$listFile" "$tmpFile"
        for component in "${components[@]}"; do
            sed -i "/^Components:/ {
            /$component/! s/$/ $component/
        }" "$tmpFile"
        done

        if ! cmp -s "$listFile" "$tmpFile"; then
            trigger_apt_update=true
            mv "$tmpFile" "$listFile"
        else
            rm "$tmpFile"
        fi
    elif [[ -f /etc/apt/sources.list ]]; then
        components=(contrib non-free)
        tmpFile=$(mktemp)
        cp /etc/apt/sources.list "$tmpFile"
        chmod --reference=/etc/apt/sources.list "$tmpFile"
        chown --reference=/etc/apt/sources.list "$tmpFile"
        for component in "${components[@]}"; do
            sed -Ei "/^[[:space:]]*deb([[:space:]]|$)/ {
                /^[[:space:]]*#/! /[[:space:]]$component([[:space:]]|$)/! s/$/ $component/
            }" "$tmpFile"
        done

        if ! cmp -s /etc/apt/sources.list "$tmpFile"; then
            if mv "$tmpFile" /etc/apt/sources.list; then
                trigger_apt_update=true
            else
                rm -f "$tmpFile"
                echo_error "Failed to update /etc/apt/sources.list"
                exit 1
            fi
        else
            rm "$tmpFile"
        fi
    fi
fi
if [[ $trigger_apt_update == "true" ]]; then
    apt_update
fi

# Install software-properties-common (provides add-apt-repository) after repos
# are already enabled, so the package is reachable even on minimal installs.
if [[ $(_os_distro) == "ubuntu" ]] && ! which add-apt-repository > /dev/null; then
    apt_install software-properties-common # Ubuntu may require universe/multiverse enabled for certain packages so we must ensure repos are enabled before deps are attempted to install
fi

# Add the Jammy toolchain PPA now that add-apt-repository is available.
if [[ $(_os_distro) == "ubuntu" ]] && [[ $(_os_codename) == "jammy" ]]; then
    if ! grep -s 'ubuntu-toolchain-r' /etc/apt/sources.list.d/ubuntu-toolchain-r-ubuntu-ppa-jammy.list 2> /dev/null | grep -q -v '^#'; then
        echo_info "Adding toolchain repo"
        add-apt-repository -y ppa:ubuntu-toolchain-r/ppa >> ${log} 2>&1
        apt_update
    fi
fi

#space-separated list of required GLOBAL SWIZZIN dependencies (NOT application specific ones)
dependencies="whiptail git sudo curl wget lsof rsyslog fail2ban apache2-utils vnstat tcl tcl-dev build-essential dirmngr apt-transport-https bc jq net-tools gnupg2 cracklib-runtime unzip ccze cron"

apt_install "${dependencies[@]}"

#shellcheck source=sources/functions/gcc
. /etc/swizzin/sources/functions/gcc
GCC_Jammy_Upgrade
