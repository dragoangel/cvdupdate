#!/bin/bash
USER_ID="${USER_ID:-0}"
SCRIPT_PATH=$(readlink -f "$0")
echo "ClamAV Private Database Mirror Updater Cron ${SCRIPT_PATH}"
CONFIG_ARGS=(--logs-directory /cvdupdate/logs --dbs-directory /cvdupdate/database --state-file /cvdupdate/database/.state.json)
if [ -n "${ENABLE_LOGS}" ] && [ "${ENABLE_LOGS}" != "false" ]; then
    CONFIG_ARGS+=( --logs-enabled)
fi
if [ -n "${LOGS_TO_KEEP}" ]; then
    if [[ "${LOGS_TO_KEEP}" =~ ^[1-9][0-9]*$ ]]; then
        CONFIG_ARGS+=( --logs-to-keep "${LOGS_TO_KEEP}")
    else
        echo "WARNING: LOGS_TO_KEEP must be a positive integer, got ${LOGS_TO_KEEP}, skipping"
    fi
fi

if [ "${USER_ID}" -ne "0" ]; then
    echo "Creating user with ID ${USER_ID}"
    useradd --create-home --home-dir /cvdupdate --uid "${USER_ID}" cvdupdate
    chown -R "${USER_ID}" /cvdupdate
    gosu cvdupdate cvdupdate config set "${CONFIG_ARGS[@]}"
else
    mkdir -p /cvdupdate/database
    if [ -n "${ENABLE_LOGS}" ] && [ "${ENABLE_LOGS}" != "false" ]; then
        mkdir -p /cvdupdate/logs
    fi
    cvdupdate config set "${CONFIG_ARGS[@]}"
fi

if [ -n "${REMOVE_DATABASES}" ]; then
    echo "Removing databases from REMOVE_DATABASES"
    IFS=',' read -ra ENTRIES <<< "${REMOVE_DATABASES}"
    for (( i=0; i<${#ENTRIES[@]}; i++ )); do
        db_name="${ENTRIES[$i]}"
        if [ -z "${db_name}" ]; then
            continue
        fi
        if [ "${USER_ID}" -ne "0" ]; then
            gosu cvdupdate cvdupdate remove "${db_name}"
        else
            cvdupdate remove "${db_name}"
        fi
    done
fi

if [ -n "${EXTRA_DATABASES}" ]; then
    echo "Adding extra databases from EXTRA_DATABASES"
    IFS=',' read -ra ENTRIES <<< "${EXTRA_DATABASES}"
    for (( i=0; i<${#ENTRIES[@]}; i++ )); do
        db_name="${ENTRIES[$i]%%:*}"
        db_url="${ENTRIES[$i]#*:}"
        if [ -z "${db_name}" ] || [ -z "${db_url}" ]; then
            echo "WARNING: skipping malformed EXTRA_DATABASES entry: '${ENTRIES[$i]}' (expected <db_name>:<db_url>)"
            continue
        fi
        if [ "${USER_ID}" -ne "0" ]; then
            gosu cvdupdate cvdupdate add --override "${db_name}" "${db_url}"
        else
            cvdupdate add --override "${db_name}" "${db_url}"
        fi
    done
fi

if [ $# -eq 0 ]; then
    set -e

    echo "Adding crontab entry"
    if [ "${USER_ID}" -ne "0" ]; then
        crontab -l | {
            cat
            echo "${CRON:-"30 */4 * * *"} /usr/sbin/gosu cvdupdate /usr/local/bin/cvdupdate update >/proc/1/fd/1 2>/proc/1/fd/2"
            echo "@reboot /usr/sbin/gosu cvdupdate /usr/local/bin/cvdupdate update >/proc/1/fd/1 2>/proc/1/fd/2"
        } | crontab -
    else
        crontab -l | {
            cat
            echo "${CRON:-"30 */4 * * *"} /usr/local/bin/cvdupdate update >/proc/1/fd/1 2>/proc/1/fd/2"
            echo "@reboot /usr/local/bin/cvdupdate update >/proc/1/fd/1 2>/proc/1/fd/2"
        } | crontab -
    fi
    cron -f
else
    if [ "${USER_ID}" -ne "0" ]; then
        exec gosu cvdupdate "$@"
    else
        exec "$@"
    fi
fi
