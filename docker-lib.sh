#!/bin/bash

declare -a __exit_callbacks
onexit() {
    __exit_callbacks[${#__exit_callbacks[@]}]="$@"
}

do_exit() {
    if [ -z "$exit_code" ] ; then
        exit_code="$1"
        local n
        n=${#__exit_callbacks[@]}
        for ((; n--; )) ; do
            eval "${__exit_callbacks[$n]}"
        done
    fi
}

EXEC() {
    do_exit 0
    exec "$@"
}

trap "do_exit 1; exit $exit_code" INT TERM QUIT
trap "do_exit 0; exit $exit_code" EXIT

onexit 'if [ -n "$tmpdir" -a -d "$tmpdir" ] ; then rm -r "$tmpdir" ; fi'

ensure_tmp() {
    if [ -z "$tmpdir" ] ; then
        tmpdir="$( mktemp -d )"
    fi
}

# poor man's CDash client
mksession() {
    local result
    ensure_tmp
    mkdir -p "$tmpdir/sessions"
    until mkdir "$result" 2> /dev/null ; do
        result="$tmpdir/sessions/$RANDOM"
    done
    echo "$result"
}

ajax() {
    local method
    local session
    local route
    local curl_args
    local arg

    method="$1" ; shift
    session="$1" ; shift
    route="$1" ; shift

    if [ "$method" '=' 'POST' ] ; then
        for arg in "$@" ; do
            curl_args="$curl_args --form '$arg'"
        done
    fi

    local oldcookies
    local newcookies

    oldcookies="$session/cookies.txt"
    newcookies="$session/cookies.tmp"

    if [ "$session" '!=' '-' ] ; then
        if [ -f "$oldcookies" ] ; then
            curl_args="$curl_args --cookie '$oldcookies'"
        fi
        curl_args="$curl_args --cookie-jar '$newcookies'"
    fi

    local port="$PORT"
    if [ -n "$port" ] ; then
        port=":$port"
    fi

    curl_args="$curl_args 'http://localhost${port}/$route"

    if [ "$method" '=' 'GET' ] ; then
        arg="$1" ; shift
        if [ -n "$arg" ] ; then
            curl_args="${curl_args}?$arg"
        fi

        for arg in "$@" ; do
            curl_args="${curl_args}&$arg"
        done
    fi

    curl_args="${curl_args}'"

    eval "curl $curl_args" 2>&-

    if [ "$session" '!=' '-' ] ; then
        if [ -f "$newcookies" ] ; then
            mv "$newcookies" "$oldcookies"
        fi
    fi

    sleep 0.2
}

get() {
    ajax GET "$@"
}

post() {
    ajax POST "$@"
}

user_prefix="__user"
user_set() {
    email="$1" ; shift
    key="$1" ; shift
    value="$1" ; shift
    email_hash="$( echo "$email" | sha1sum | cut -d\  -f 1 )"
    eval "${user_prefix}_${email_hash}_${key}=\"${value}\""
}

user_get() {
    email="$1" ; shift
    key="$1" ; shift
    email_hash="$( echo "$email" | sha1sum | cut -d\  -f 1 )"
    eval "echo \"\$${user_prefix}_${email_hash}_${key}\""
}
