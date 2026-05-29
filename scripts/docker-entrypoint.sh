#!/bin/bash
USER_ID="${USER_ID:-0}"
SCRIPT_PATH=$(readlink -f "$0")
echo "ClamAV Private Database Mirror Updater Cron ${SCRIPT_PATH}"
if [ "${USER_ID}" -ne "0" ]; then
    echo "Creating user with ID ${USER_ID}"
    useradd --create-home --home-dir /cvdupdate --uid "${USER_ID}" cvdupdate
    chown -R "${USER_ID}" /cvdupdate
    gosu cvdupdate cvdupdate config set --logdir /cvdupdate/logs
    gosu cvdupdate cvdupdate config set --dbdir /cvdupdate/database
else
    mkdir -p /cvdupdate/{logs,database}
    cvdupdate config set --logdir /cvdupdate/logs
    cvdupdate config set --dbdir /cvdupdate/database
fi

if [ $# -eq 0 ]; then
    set -e

    echo "Adding crontab entry"
    cron_start_marker="# cvdupdate managed cron start"
    cron_end_marker="# cvdupdate managed cron end"
    if [ "${USER_ID}" -ne "0" ]; then
        timed_command="${CRON:-"30 */4 * * *"} /usr/sbin/gosu cvdupdate /usr/local/bin/cvdupdate update >/proc/1/fd/1 2>/proc/1/fd/2"
        reboot_command="@reboot /usr/sbin/gosu cvdupdate /usr/local/bin/cvdupdate update >/proc/1/fd/1 2>/proc/1/fd/2"
    else
        timed_command="${CRON:-"30 */4 * * *"} /usr/local/bin/cvdupdate update >/proc/1/fd/1 2>/proc/1/fd/2"
        reboot_command="@reboot /usr/local/bin/cvdupdate update >/proc/1/fd/1 2>/proc/1/fd/2"
    fi
    unmanaged_crontab="$(
        crontab -l 2>/dev/null \
            | awk -v start="$cron_start_marker" -v end="$cron_end_marker" '
                $0 == start { managed = 1; next }
                $0 == end { managed = 0; next }
                managed { next }
                /\/usr\/local\/bin\/cvdupdate update >\/proc\/1\/fd\/1 2>\/proc\/1\/fd\/2$/ { next }
                { print }
            ' || true
    )"
    {
        if [ -n "$unmanaged_crontab" ]; then
            printf '%s\n' "$unmanaged_crontab"
        fi
        printf '%s\n' "$cron_start_marker"
        printf '%s\n' "$timed_command"
        printf '%s\n' "$reboot_command"
        printf '%s\n' "$cron_end_marker"
    } | crontab -

    cron -f
else
    if [ "${USER_ID}" -ne "0" ]; then
        exec gosu cvdupdate "$@"
    else
        exec "$@"
    fi
fi
