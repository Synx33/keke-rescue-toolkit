#!/bin/sh
if [ "$(tty)" = "/dev/tty1" ] && [ ! -f /tmp/.setup_done ]; then
    touch /tmp/.setup_done
    # Boot animation (KEKE logo + loading bar)
    sh /usr/local/bin/boot-animation
    # Instant setup (just file copies + drivers, no package installation)
    sh /usr/local/bin/auto-setup
    # Go straight to toolkit
    sh /usr/local/bin/toolkit-menu
fi
printf '\n  \033[1;33mTo run toolkit: sh /usr/local/bin/toolkit-menu\033[0m\n\n'
