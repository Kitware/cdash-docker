#!/bin/bash

DEBUG() {
    if [ -n "$DEBUG" ] ; then
        echo -n "DEBUG:: "
        echo "$@"
    fi
}

source "/docker-lib.sh"

if [ -z "$CDASH_ROOT_ADMIN_PASS" ] ; then
    cat << ____EOF
error: This container requires the CDASH_ROOT_ADMIN_PASS
       environment variable to be defined.
____EOF
    exit 1
fi 1>&2

config_variables="CDASH_DB_HOST:STRING"
config_variables="${config_variables} CDASH_DB_LOGIN:STRING"
config_variables="${config_variables} CDASH_DB_PORT:STRING"
config_variables="${config_variables} CDASH_DB_PASS:STRING"
config_variables="${config_variables} CDASH_DB_NAME:STRING"
config_variables="${config_variables} CDASH_DB_TYPE:STRING"
config_variables="${config_variables} CDASH_DB_CONNECTION_TYPE:STRING"
config_variables="${config_variables} CDASH_EMAILADMIN:STRING"
config_variables="${config_variables} CDASH_EMAIL_FROM:STRING"
config_variables="${config_variables} CDASH_EMAIL_REPLY:STRING"
config_variables="${config_variables} CDASH_EMAIL_SMTP_HOST:STRING"
config_variables="${config_variables} CDASH_EMAIL_SMTP_PORT:INT"
config_variables="${config_variables} CDASH_EMAIL_SMTP_ENCRYPTION:STRING"
config_variables="${config_variables} CDASH_EMAIL_SMTP_LOGIN:STRING"
config_variables="${config_variables} CDASH_EMAIL_SMTP_PASS:STRING"
config_variables="${config_variables} CDASH_REGISTRATION_EMAIL_VERIFY:BOOL"
config_variables="${config_variables} CDASH_USE_SENDGRID:BOOL"
config_variables="${config_variables} CDASH_SENDGRID_API_KEY:STRING"
config_variables="${config_variables} CDASH_COOKIE_EXPIRATION_TIME:STRING"
config_variables="${config_variables} CDASH_MINIMUM_PASSWORD_LENGTH:INT"
config_variables="${config_variables} CDASH_MINIMUM_PASSWORD_COMPLEXITY:INT"
config_variables="${config_variables} CDASH_PASSWORD_COMPLEXITY_COUNT:INT"
config_variables="${config_variables} CDASH_USE_HTTPS:STRING"
config_variables="${config_variables} CDASH_SERVER_NAME:STRING"
config_variables="${config_variables} CDASH_SERVER_PORT:STRING"

tmp_config_file="/var/www/cdash/config/config.tmp.php"
tmp_hash_file="/var/www/cdash/config/config.tmp.checksum"
local_config_file="/var/www/cdash/config/config.local.php"

(
    echo '<?php'
    for token in $config_variables ; do
        entry=(${token/:/ })
        var_name=${entry[0]}
        var_type=${entry[1]}

        # skip the variable if the user did not set it
        if eval "[ -z \${$var_name+x} ]" ; then
            continue
        fi

        eval "var_value=\"\$$var_name\""

        quote=""
        if [ -z "$var_type" -o "$var_type" '=' 'STRING' ] ; then
            quote="'"
        fi

        echo "\$$var_name = ${quote}${var_value}${quote};"
    done
) | tee "$tmp_config_file" | sha1sum > "$tmp_hash_file"

( sha1sum --check --status "$tmp_hash_file" < "$local_config_file" ) 2>/dev/null
if [ "$?" '!=' '0' ] ; then
    mv "$tmp_config_file" "$local_config_file"
fi
rm "$tmp_hash_file"

PORT="$(( (RANDOM % 20000) + 10000 ))"
sed -i 's/^Listen [0-9][0-9]*/Listen '"$PORT"'/g' /etc/apache2/ports.conf
head /etc/apache2/ports.conf
sed -i 's/^<VirtualHost \*:[0-9][0-9]*>/<VirtualHost \*:'"$PORT"'>/g' \
    /etc/apache2/sites-enabled/000-default.conf
echo "\$CDASH_FULL_EMAIL_WHEN_ADDING_USER = '1';" >> "$local_config_file"

/usr/sbin/apache2ctl -D FOREGROUND &
apache_pid="$!"
onexit '
if [ -n "$apache_pid" ] ; then
    /usr/sbin/apache2ctl graceful-stop
    wait
fi'

sleep 10

# ENSURE ROOT ADMIN USER
final_root_pass="$CDASH_ROOT_ADMIN_PASS"
if [ -n "$CDASH_ROOT_ADMIN_NEW_PASS" ] ; then
    final_root_pass="$CDASH_ROOT_ADMIN_NEW_PASS"
fi

post - install.php admin_email='rootadmin@docker.container' \
                   admin_password="$final_root_pass"        \
                   Submit=Install &> /dev/null

if [ -n "$CDASH_ROOT_ADMIN_NEW_PASS" ] ; then
    root_session="$( mksession )"
    post "$root_session" user.php login='rootadmin@docker.container' \
                                  passwd="$final_root_pass"          \
                                  sent='Login >>'                    \
        | grep 'Wrong email or password'                             \
        | ( read X ; DEBUG "|$X|" ; [ -z "$X" ] )

    if [ "$?" '!=' '0' -a \
         "$CDASH_ROOT_ADMIN_PASS" '!=' "$final_root_pass" ] ; then

        # login failure
        post "$root_session" user.php login='rootadmin@docker.container' \
                                      passwd="$CDASH_ROOT_ADMIN_PASS"    \
                                      sent='Login >>'                    \
            | grep 'Wrong email or password'                             \
            | ( read X ; DEBUG "|$X|" ; [ -z "$X" ] )

        if [ "$?" '=' '0' ] ; then
            post "$root_session" editUser.php      \
                oldpasswd="$CDASH_ROOT_ADMIN_PASS" \
                passwd="$final_root_pass"          \
                passwd2="$final_root_pass"         \
                updatepassword='Update Password' &> /dev/null
        else
            echo "Warning: could not log in as the root admin user:" \
                 "Wrong email or password" >&2
            root_login_failed=1
        fi
    fi
fi

if [ "$root_login_failed" '!=' '1' ] ; then
    declare -a users_list
    users_file="/cdash_users"
    if [ -f "$users_file" ] ; then
        oldifs="$IFS"
        IFS=$'\n'
        exec 3<"$users_file"
        while read -u 3 line ; do
            processed_line="$( echo "$line" |
                     sed $'s/\t\t*/ /g' | sed 's/  */ /g' | sed 's/#.*//g')"
            if [ -z "$( echo "$processed_line" | sed $'s/[ \t]*//g' )" ] ; then
                DEBUG "SKIPPING LINE"
                DEBUG "[$line]"
                continue
            fi
            eval "entry=($processed_line)"

            disp="${entry[0]}"
            if [ "$disp" '=' 'delete' ] ; then
                email="${entry[1]}"
                pass="${entry[2]}"
                user_set "$email" disp "${disp}"
                user_set "$email" pass "${pass}"
            fi

            if [ "${#entry[@]}" '=' 6 ] ; then
                disp="${entry[0]}"
                email="${entry[1]}"
                pass="${entry[2]}"
                first="${entry[3]}"
                last="${entry[4]}"
                institution="${entry[5]}"
            fi

            if [ "${#entry[@]}" '=' 7 ] ; then
                disp="${entry[0]}"
                email="${entry[1]}"
                pass="${entry[2]}"
                newpass="${entry[3]}"
                first="${entry[4]}"
                last="${entry[5]}"
                institution="${entry[6]}"

                if [ "$( user_get "$email" disp )" '=' 'user' ] ; then
                    user_set "$email" newpass "$newpass"
                fi
            fi

            if [ "$disp" '!=' 'delete' ] ; then
                user_set "$email" disp        "$disp"
                user_set "$email" pass        "$pass"
                user_set "$email" first       "$first"
                user_set "$email" last        "$last"
                user_set "$email" institution "$institution"
            fi

            if [ "$( user_get "$email" listed )" '!=' 1 ] ; then
                users_list[${#users_list[@]}]="$email"
                user_set "$email" listed 1
            fi

            DEBUG "PARSED USER ENTRY FROM FILE"
            DEBUG "  $email"
            DEBUG "  disposition: $disp"
            DEBUG "  password: $pass"
            if [ "$disp" '!=' 'delete' ] ; then
                DEBUG "  new pass: $newpass"
                DEBUG "  First Name: $first"
                DEBUG "  Last Name: $last"
                DEBUG "  Institution: $institution"
            fi
        done
        exec 3<&-
        IFS="$oldifs"
    fi

    eval "env_list=($(
        echo "$CDASH_USER_LIST" | sed 's/,/" "/g' | sed 's/\(.*\)/"\1"/g' ))"

    for (( i=0; i < ${#env_list[@]} ; ++i )) ; do
        token="${env_list[$i]}"
        if [ -z "$token" ] ; then
            continue
        fi

        eval "email=\"\$CDASH_USER_${token}_EMAIL\""
        if [ "$( user_get "$email" listed )" '!=' 1 ] ; then
            users_list[${#users_list[@]}]="$email"
            user_set "$email" listed 1
        fi

        for tuple in 'disp:DISPOSITION' 'pass:PASSWORD' 'first:FIRST_NAME' \
                     'last:LAST_NAME' 'newpass:NEW_PASSWORD' \
                     'institution:INSTITUTION' ; do
            param="${tuple/:*}"
            variable="${tuple/*:}"

            eval "value=\"\$CDASH_USER_${token}_${variable}\""
            if [ -n "$value" ] ; then
                user_set "$email" "$param" "$value"
            fi
        done

        DEBUG "PROCESSED USER ENTRY FROM ENVIRONMENT VARIABLE"
        DEBUG "  $email"
        DEBUG "  disposition: $disp"
        DEBUG "  password: $pass"
        DEBUG "  new pass: $newpass"
        DEBUG "  First Name: $first"
        DEBUG "  Last Name: $last"
        DEBUG "  Institution: $institution"
    done

    DEBUG "BEGIN DUMP OF USER TABLE"
    for (( i=0; i < ${#users_list[@]} ; ++i )) ; do
        email="${users_list[$i]}"

        for tuple in "disp" "pass" "newpass" "first:John/Jane" \
                     "last:Doe" "institution:none" ; do
            fragment="${tuple/:*}"
            tuple="${tuple:$(( ${#fragment} + 1 ))}"
            param="$fragment"
            fragment="${tuple/:*}"
            tuple="${tuple:$(( ${#fragment} + 1 ))}"
            default="$fragment"

            value="$( user_get "$email" "$param" )"
            if [ -z "$value" -a -n "$default" ] ; then
                value="$default"
            fi
            eval "${param}=\"$value\""
        done
        DEBUG "$i:"
        DEBUG "  $email"
        DEBUG "  disposition: $disp"
        DEBUG "  password: $pass"
        DEBUG "  new pass: $newpass"
        DEBUG "  First Name: $first"
        DEBUG "  Last Name: $last"
        DEBUG "  Institution: $institution"
    done

    for (( i=0; i < ${#users_list[@]} ; ++i )) ; do
        email="${users_list[$i]}"
        if [ "$email" '=' 'rootadmin@docker.conatiner' ] ; then
            echo 'Warning: refusing to modify the root admin account!' \
                 "Use the CDASH_ROOT_ADMIN_NEW_PASS environment variable" \
                 "to update the root account password." >&2
            continue
        fi

        if [ -z "$root_session" ] ; then
            root_session="$( mksession )"

            # LOGIN AS ROOT ADMIN USER
            post "$root_session" user.php              \
                    login='rootadmin@docker.container' \
                    passwd="$final_root_pass"          \
                    sent='Login >>'                    \
                | grep 'Wrong email or password'       \
                | ( read X ; DEBUG "|$X|" ; [ -z "$X" ] )

            if [ "$?" '!=' '0' ] ; then
                echo "Warning: could not log in as the root admin user:" \
                     "Wrong email or password" >&2
                break
            fi
        fi

        for tuple in "disp" "pass" "newpass" "first:John/Jane" \
                     "last:Doe" "institution:none" ; do
            fragment="${tuple/:*}"
            tuple="${tuple:$(( ${#fragment} + 1 ))}"
            param="$fragment"
            fragment="${tuple/:*}"
            tuple="${tuple:$(( ${#fragment} + 1 ))}"
            default="$fragment"

            value="$( user_get "$email" "$param" )"
            if [ -z "$value" -a -n "$default" ] ; then
                value="$default"
            fi
            eval "${param}=\"$value\""
        done

        ids=($(                                                    \
            get "$root_session" ajax/findusers.php search="$email" \
                | grep '<input'                                    \
                | grep 'name="userid"'                             \
                | grep 'type="hidden"'                             \
                | sed 's/..*value="\([0-9][0-9]*\)"..*/\1/g'))

        user_id="${ids[0]}"

        if [ "$disp" '=' 'delete' ] ; then
            # REMOVE USER
            DEBUG "REMOVING USER: $email"
            if [ -n "$user_id" ] ; then
                post "$root_session" manageUsers.php          \
                                     userid="$user_id"        \
                                     removeuser="remove user" &> /dev/null
            else
                echo "Warning: could not remove user" \
                     "$email: user not found" >&2
            fi

            continue
        fi

        final_pass="$pass"
        if [ -n "$newpass" ] ; then
            final_pass="$newpass"
        fi

        login_pass="$pass"

        if [ -z "$user_id" ] ; then
            login_pass="$final_pass"

            # CREATE USER
            DEBUG "CREATING USER: $email"
            post "$root_session" manageUsers.php             \
                                  fname="$first"             \
                                  lname="$last"              \
                                  email="$email"             \
                                  passwd="$final_pass"       \
                                  passwd2="$final_pass"      \
                                  institution="$institution" \
                                  adduser='Add user >>' &> /dev/null

            ids=($(                                                    \
                get "$root_session" ajax/findusers.php search="$email" \
                    | grep '<input'                                    \
                    | grep 'name="userid"'                             \
                    | grep 'type="hidden"'                             \
                    | sed 's/..*value="\([0-9][0-9]*\)"..*/\1/g'))

            user_id="${ids[0]}"

            if [ -z "$user_id" ] ; then
                echo "Warning: unable to create user account" \
                     "$email: unknown error" >&2
                continue
            fi
         fi

         if [ "$disp" '=' 'admin' ] ; then
             DEBUG "PROMOTING USER: $email"
             post "$root_session" manageUsers.php        \
                                  userid="$user_id"      \
                                  makeadmin="make admin" &> /dev/null
         fi

         if [ "$disp" '=' 'user' ] ; then
             DEBUG "DEMOTING USER: $email"
             post "$root_session" manageUsers.php                   \
                                  userid="$user_id"                 \
                                  makenormaluser="make normal user" \
                                  &> /dev/null
         fi

        user_session="$( mksession )"

        # LOGIN AS NORMAL USER
        login_success=0
        DEBUG "LOGGING IN AS USER: $email"
        post "$user_session" user.php login="$email"        \
                                      passwd="$login_pass"  \
                                      sent='Login >>'       \
            | grep 'Wrong email or password'                \
            | ( read X ; DEBUG "|$X|" ; [ -z "$X" ] )

        if [ "$?" '=' '0' ] ; then # login success
            login_success=1
        elif [ "$login_pass" '!=' "$newpass" ] ; then # login failure
            login_pass="$newpass"
            DEBUG "LOGGING IN (FALLBACK) AS USER: $email"
            post "$user_session" user.php login="$email"        \
                                          passwd="$login_pass"  \
                                          sent='Login >>'       \
                | grep 'Wrong email or password'                \
                | ( read X ; DEBUG "|$X|" ; [ -z "$X" ] )

            if [ "$?" '=' '0' ] ; then
                login_success=1
            fi
        fi

        if [ "$login_success" '=' '0' ] ; then
            echo "Warning: could not log in as user" \
                 "$email: Wrong email or password" >&2
            continue
        fi

        DEBUG "UPDATING USER PROFILE: $email"
        post "$user_session" editUser.php fname="$first"                 \
                                          lname="$last"                  \
                                          email="$email"                 \
                                          institution="$institution"     \
                                          updateprofile='Update Profile' \
                                          &> /dev/null

        if [ -n "$newpass" -a "$login_pass" '!=' "$newpass" ] ; then
            # update user's password
            DEBUG "UPDATING USER PASSWORD: $email"
            post "$user_session" editUser.php    \
                oldpasswd="$login_pass"          \
                passwd="$newpass"                \
                passwd2="$newpass"               \
                updatepassword='Update Password' &> /dev/null
        fi

        get "$user_session" user.php logout=1 &> /dev/null
    done

    get "$root_session" user.php logout=1 &> /dev/null
fi

/usr/sbin/apache2ctl graceful-stop
unset apache_pid
wait
sleep 10

sed -i 's/^Listen [0-9][0-9]*/Listen 80/g' /etc/apache2/ports.conf
sed -i 's/^<VirtualHost \*:[0-9][0-9]*>/<VirtualHost \*:80>/g' \
    /etc/apache2/sites-enabled/000-default.conf
tmp="$( mktemp )"
head -n -1 "$local_config_file" > "$tmp"
cat "$tmp" > "$local_config_file"
rm "$tmp"

EXEC /usr/sbin/apache2ctl -D FOREGROUND
