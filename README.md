# cdash-docker
Deploy a cdash instance with docker and zero guess work!

## How?

Build with docker:

```bash
docker build -t "kitware/cdash-docker" .
```

...or build with docker-compose

```bash
docker-compose build
```

## Deploy example application using docker-compose

See `docker-compose.yml` for an example of how to deploy using the
`cdash-docker` image.  Add your own customizations, or deploy the example as-is!

```bash
docker-compose up -d
```

Check on your instance's status:

```bash
docker-compose ps
```

Once docker reports that cdash is "healthy", you're good to go!  Browse your
cdash instance at `localhost:8080`.

## Container Variables

### `CDASH_CONFIG`

The contents, verbatim, to be included in the local CDash configuration file
(`/var/www/cdash/config/config.local.php`), excluding the initial `<?php` line.
When running the container on the command line, consider writing the contents to
a local file:

```bash
$EDITOR local-configuration.php
...
docker run \
    -e CDASH_CONFIG="$( cat local-configuration.php )" \
    ... \
    kitware/cdash-docker
```

Note: When setting this variable in a docker-compose file, take care to ensure
that dollar signs (`$`) are properly escaped.  Otherwise, the resulting contents
of the file may be subject to variable interpolation.

Example:

```YAML

...

  # wrong: this string syntax is subject to interpolation
  # The contents will depend on the CDASH_DB_... variables as they are set at
  # container creation time
  CDASH_CONFIG: |
    $CDASH_DB_HOST = 'mysql';
    $CDASH_DB_NAME = 'cdash';
    $CDASH_DB_TYPE = 'mysql';
    ...

  # correct: use $$ to represent a literal `$`
  CDASH_CONFIG: |
    $$CDASH_DB_HOST = 'mysql';
    $$CDASH_DB_NAME = 'cdash';
    $$CDASH_DB_TYPE = 'mysql';
    ...

...
```

### `CDASH_ROOT_ADMIN_PASS`

The password for the "root" administrator user, or the initial administrator
user that is created during the CDash `install.php` procedure.  This is the only
variable that is strictly required.

The initial "root" administrator user is managed by the container.  The
container uses this user account to log in and provision the service as well as
set up static users.  This account is not meant to be used by an actual
administrator.  To set up a predefined administrator account, see
`CDASH_STATIC_USERS`.

### `CDASH_ROOT_ADMIN_NEW_PASS`

Set this variable to change the password for the root administrator account.  If
set, the container will attempt to use this password when logging in as the root
account.  If the login is unsuccessful, it will try logging in using the
(presumably former) password set in `CDASH_ROOT_ADMIN_PASS`.  If this second
attempt is successful, it will update the root account so that its password is
reset to the value of `CDASH_ROOT_ADMIN_NEW_PASS`.

### `CDASH_STATIC_USERS`

A multiline value representing the set of user accounts to prepare as part of
the container's initialization process.  This value may contain comments that
start with `#` and lines with only white space; these parts of the text are
ignored.

Each user account identified in the set is created using the information
provided.  If the account already exists, its details are modified to match the
information provided.  Existing accounts that are not identified in the set are
not modified.

The representation for each user account begins with a line of the following
form:

```
[USER|ADMIN|DELETE] EMAIL PASSWORD [NEW_PASSWORD]
```

Where `EMAIL` is the user's email address, `PASSWORD` is the user's password,
and `NEW_PASSWORD` (if provided) is the user's new password.  If `NEW_PASSWORD`
is provided, the user's password is updated using the same procedure as that
with `CDASH_ROOT_ADMIN_NEW_PASS`.

This entry line may begin with an additional token.  A token of `USER` indicates
that the entry is for a normal (non-admin) account.  A token of `ADMIN`
indicates that the entry is for an administrator account.  A token of `DELETE`
indicates that any account with the given email (if found) should be deleted.
If no such token is provided, `USER` is assumed by default.

An entry may include an additional, optional line.  Such lines must be of the
following form:

```
[INFO] FIRST_NAME [LAST_NAME] [INSTITUTION]
```

Where `FIRST_NAME` is the user's first name, `LAST_NAME` is the user's last
name, and `INSTITUTION` is the name of the institution with which the user is
affiliated.

This second line may begin with an additional token with the value `INFO`, which
may be provided to distinguish this second line from a line representing a new
user account, in case the user's first name contains an `@` character.  For such
unusual cases, include this token so that the name is not mistaken for an email
address.

Note: for `DELETE` entries, all that is needed is the account's email address,
and for either `PASSWORD` or `NEW_PASSWORD` (if provided) to be set to the
password needed to log in as that user.  You may provide additional information
for the account, but it will not be used since the account will be deleted.

Note: for tokens with spaces, wrap them in quotes (`"`).
