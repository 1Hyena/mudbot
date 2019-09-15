#!/bin/bash
################################################################################
# Example usage: ./jesus.sh config.json (acc-pass)                             #
################################################################################
BOT_CONF="${1}"                                                                #
ACC_PASS="${2}"                                                                #
################################################################################
# This bot connects to the MUD server specified in the configuration file and  #
# periodically captures the online player list and the state of a given room.  #
################################################################################
DATE_FORMAT="%Y-%m-%d %H:%M:%S"
BOT_FPS=8
BOT_NAME=""
MUD_HOST=""
MUD_PORT=""
ACC_NAME=""
PLR_NAME=""
CAM_ADDR=""
CAM_AUTH=""
CAM_HASH=""
MIN_CHAR=10
MAX_CHAR=6000
PING_PERIOD=10
EXTRA_CAM=0

log() {
    now=`date +"${DATE_FORMAT}"`
    printf "\033[1;36m%s\033[0m :: %s\n" "${now}" "${1}" >/dev/stderr
}

if [ "${BOT_FPS}" -le "0" ]; then
    log "Invalid FPS."
    exit
fi

if [ "${PING_PERIOD}" -le "0" ]; then
    log "Invalid ping period."
    exit
fi

################################################################################
# Use a lockfile containing the pid of the running process. If this script     #
# crashes and leaves the lockfile around, it will have a different pid so it   #
# will not prevent it from running again.                                      #
################################################################################
lf=/tmp/NDtGztoqmiB7hQBQ
touch $lf
read lastPID < $lf

if [ ! -z "$lastPID" -a -d /proc/$lastPID ]
then
    log "Another instance of this bot is already running!"
    exit
fi
echo $$ > $lf

if [ -z "$BOT_CONF" ] ; then
    log "Configuration file not provided, exiting."
    exit
fi

if [[ -r ${BOT_CONF} ]] ; then
    config=$(<"$BOT_CONF")
    BOT_NAME=`printf "%s" "${config}" | jq -r -M '.title | select (.!=null)'`
    MUD_HOST=`printf "%s" "${config}" | jq -r -M '.["mud-host"] | select (.!=null)'`
    MUD_PORT=`printf "%s" "${config}" | jq -r -M '.["mud-port"] | select (.!=null)'`
    ACC_NAME=`printf "%s" "${config}" | jq -r -M '.["acc-name"] | select (.!=null)'`
    PLR_NAME=`printf "%s" "${config}" | jq -r -M '.["plr-name"] | select (.!=null)'`
    CAM_ADDR=`printf "%s" "${config}" | jq -r -M '.["cam-addr"] | select (.!=null)'`
    CAM_AUTH=`printf "%s" "${config}" | jq -r -M '.["cam-auth"] | select (.!=null)'`

    if [ -z "${ACC_PASS}" ] ; then
        ACC_PASS=`printf "%s" "${config}" | jq -r -M '.["acc-pass"] | select (.!=null)'`
    fi

    if [ ! -z "${BOT_NAME}" ] ; then
        printf "\033]0;%s\007" "${BOT_NAME}"
    fi
else
    log "Failed to read the configuration file."
    exit
fi

if [ -z "${MUD_HOST}" ] ; then
    log "MUD host not provided, exiting."
    exit
fi

if [ -z "${MUD_PORT}" ] ; then
    log "MUD port not provided, exiting."
    exit
fi

if [ -z "${ACC_NAME}" ] ; then
    log "Account name not provided, exiting."
    exit
fi

if [ -z "${ACC_PASS}" ] ; then
    log "Account password not provided, exiting."
    exit
fi

if [ -z "${PLR_NAME}" ] ; then
    log "Player name not provided, exiting."
    exit
fi

if [ -z "${CAM_ADDR}" ] ; then
    log "Cam address not provided, exiting."
    exit
fi

if [ -z "${CAM_AUTH}" ] ; then
    log "Cam authentication header not provided, exiting."
    exit
fi

log "Jesus Bot has started."

close_coproc()
{
    eval "exec ${COPROC[0]}<&- ${COPROC[1]}>&-"

    if [ ! -z "${COPROC_PID}" -a -d /proc/${COPROC_PID} ]
    then
        kill -KILL "${COPROC_PID}"
    fi
}

cleanup()
{
    if command >&${COPROC[0]}
    then
        log "Closing connection to ${MUD_HOST}:${MUD_PORT}."
        close_coproc
    fi

    log "Jesus Bot has finished."
}

sig_int()
{
    # Run if user hits control-c.
    printf "\n" >/dev/stderr
    log "Caught signal (SIGINT)."
    cleanup
    exit
}

sig_quit()
{
    log "Caught signal (SIGQUIT)."
    cleanup
    exit
}

sig_term()
{
    log "Caught signal (SIGTERM)."
    cleanup
    exit
}

trap sig_int SIGINT
trap sig_term SIGTERM
trap sig_quit SIGQUIT

coproc socat -t 3 -,ignoreeof TCP:${MUD_HOST}:${MUD_PORT},shut-none

sleep 1

if [ ! -z "${COPROC_PID}" -a -d /proc/${COPROC_PID} ]; then
    log "Connected to ${MUD_HOST}:${MUD_PORT}."
else
    log "Connection to ${MUD_HOST}:${MUD_PORT} could not be established."
    exit
fi

printf "%s\n" "${ACC_NAME}" >&${COPROC[1]}
printf "%s\n" "${ACC_PASS}" >&${COPROC[1]}
printf "play\n%s\n \n \nset prompt off\n" "${PLR_NAME}" >&${COPROC[1]}

FRAME=0
READ_TIMEOUT=`bc <<< "scale = 3; 1 / ${BOT_FPS}"`
READ_TIMEOUT=`LC_NUMERIC=C printf "%.3f" "${READ_TIMEOUT}"`
log "Read timeout is ${READ_TIMEOUT} seconds."

ping_time=0
line=""

capturing=""
pagebuf=""

while :
do
    if [ "${BASH_VERSINFO[0]}" -ge "4" ] && [ "${BASH_VERSINFO[1]}" -ge "4" ]; then
        IFS= read -t ${READ_TIMEOUT} -N 1 -r -u "${COPROC[0]}" byte
        exit_code="$?"
    else
        # Workaround for the below bug:
        # https://ftp.gnu.org/gnu/bash/bash-4.4-patches/bash44-010

        if [ ! -z "${COPROC_PID}" -a -d /proc/${COPROC_PID} ]; then
            IFS= read -t 0 -r -u "${COPROC[0]}"
            exit_code="$?"

            if [ "${exit_code}" -eq "0" ]; then
                IFS= read -N 1 -r -u "${COPROC[0]}" byte
                exit_code="$?"
            else
                sleep "${READ_TIMEOUT}"
                exit_code="142"
            fi
        else
            exit_code="1"
        fi
    fi

    if [ "${exit_code}" -gt "128" ]; then
        if [ "${ping_time}" -eq "0" ]; then
            period=${BOT_FPS}
            ((period*=PING_PERIOD))
            if [[ $(( ${FRAME} % ${period} )) == 0 ]]; then
                printf "tell self begin\n" >&${COPROC[1]}
                ((ping_time++))
            fi
        elif [ "${ping_time}" -ge "${PING_PERIOD}" ]; then
            ping_time=0
            log "Ping timeout! Shutting down."
            close_coproc
            exit
        elif [ "${ping_time}" -gt "0" ]; then
            if [[ $(( ${FRAME} % ${BOT_FPS} )) == 0 ]]; then
                ((ping_time++))
            fi
        fi

        ((FRAME++))
    elif [ "${exit_code}" -eq "0" ]; then
        if [ "${byte-}" = $'\n' ]; then
            if [ ! -z "${capturing}" ] ; then
                if [[ ${line} == "You tell yourself "* ]] && [[ ${line} == *"newline"* ]]; then
                    line=" "
                fi
            fi

            if [[ ${line} == "You tell yourself "* ]] && [[ ${line} == *"begin"* ]]; then
                if (( RANDOM % 10 == 0 )); then
                    EXTRA_CAM=$(($MIN_CHAR + RANDOM % $MAX_CHAR))
                fi

                ping_time=0
                capturing="yes"
                printf "count\ntell self newline\nat 3005 look\ntell self newline\nat 3014 look\n\ntell self newline\nat %s. look\ntell self end\n" "${EXTRA_CAM}" >&${COPROC[1]}
                log "Capturing output."
            elif [[ ${line} == "You tell yourself "* ]] && [[ ${line} == *"end"* ]]; then
                capturing=""

                cam_hash=`printf "%s" "${pagebuf}" | sha256sum | head -c 64`
                if [[ ${cam_hash} != ${CAM_HASH} ]] ; then
                    printf "%s\n" "${pagebuf}" >/dev/stderr
                    utc_min=`date +%s`
                    ((utc_min/=60))

                    datebuf=`date +"${DATE_FORMAT}"`
                    pagebuf=`printf "%s\n%s" "${datebuf}" "${pagebuf}"`

                    html=`printf "%s" "${pagebuf}" | ansi2html -s mint-terminal`
                    auth=`printf "%s%s%s" "${html}" "${CAM_AUTH}" "${utc_min}" | sha256sum | head -c 64`
                    size=`printf "%s" "${html}" | wc --bytes`

                    log "Uploading the HTML (${size} bytes)."
                    response=`printf "%s" "${html}" | curl -s --header "X-Auth: ${auth}" -X POST --data-binary @- "${CAM_ADDR}"`

                    if [ ! -z "${response}" ] ; then
                        if [[ ${response} != ${auth} ]] ; then
                            log "${response}"
                        else
                            CAM_HASH="${cam_hash}"
                        fi
                    fi
                else
                    log "Nothing has changed."
                fi

                pagebuf=""
            elif [[ ${line} == "[ LOG ::"* ]] ; then
                log "${line}"
                if [[ ${line} == *"(PK)"* ]] && [[ ${line} == *"killed by"* ]]; then
                    # Someone was killed by another player. Let's turn our extra
                    # camera to the room where this happened.

                    room_vnum=$(line#*# | cut -f 1 -d " ")

                    if [ ! -z "${room_vnum##*[!0-9]*}" ] ; then
                        log "Turning the extra camera to room #${room_vnum}."
                        EXTRA_CAM="${room_vnum}"
                    fi
                fi
            elif [[ ${line} == " Hyena"* ]] ; then # Debug segment, remove this
                log "${line}"
                if [[ ${line} == *"(PK)"* ]] && [[ ${line} == *"killed by"* ]]; then
                    # Someone was killed by another player. Let's turn our extra
                    # camera to the room where this happened.

                    room_vnum=$(printf "%s" "${line#*#}" | cut -f 1 -d " ")

                    if [ ! -z "${room_vnum##*[!0-9]*}"    ] \
                    && [ "${room_vnum}" != "${EXTRA_CAM}" ] ; then
                        log "Turning the extra camera to room #${room_vnum}."
                        EXTRA_CAM="${room_vnum}"
                    fi
                fi
            elif [ ! -z "${capturing}" ] ; then
                hexval=$(xxd -p <<< "${line}" | tr -d '\n')

                if [[ ${hexval} == "1b5b313b33336d"* ]] \
                && [[ ${hexval} == *"1b5b306d281b5b313b33306d48696465"* ]]
                then
                    # The above matches for lines beginning with '*[1;33m'
                    # and then containing '*[0m(*[1;30mHide' where * is ESC.
                    log "Skipping a hiding character: ${line}"
                elif [[ ${line} != "No such location."* ]] ; then
                    pagebuf=`printf "%s\n%s" "${pagebuf}" "${line}"`
                fi
            fi

            line=""
        elif [ "${byte-}" != $'\r' ]; then
            line+="${byte}"
        fi
    else
        log "Connection closed (read exits with code ${exit_code})."
        close_coproc
        exit
    fi
done

