# !/bin/bash

DEFAULT_USER=$(whoami)
DEFAULT_PASSWORD="password"
DEFAULT_DB=$(whoami)
DEFAULT_SCHEMA="public"

function create_superuser() {
  sudo su - postgres -c "
  psql \
    -c \"
      CREATE USER $DEFAULT_USER
      WITH PASSWORD '$DEFAULT_PASSWORD'
      CREATEDB;

      ALTER USER $DEFAULT_USER WITH
      LOGIN
      SUPERUSER
      INHERIT
      CREATEDB
      CREATEROLE
      REPLICATION;
    \"
  "
}

function connect() {
  PGPASSWORD=$DEFAULT_PASSWORD psql \
    -h localhost \
    -U $DEFAULT_USER postgres
}

function drop_db() {
  echo "dropping database $1"

  PGPASSWORD=$DEFAULT_PASSWORD dropdb \
    --if-exists \
    -U $DEFAULT_USER \
    $1
}

function create_db() {
  echo "creating database $1"

  PGPASSWORD=$DEFAULT_PASSWORD createdb \
    -U $DEFAULT_USER \
    -O $DEFAULT_USER \
    $1
}

function set_default_privileges() {
  echo "
    Setting default privileges for user $1 
    TABLES, SEQUENCES, FUNCTIONS, TYPES ON $2
  "

  PGPASSWORD=$DEFAULT_PASSWORD psql \
    -U $1 \
    -c "

    GRANT ALL ON DATABASE $2 
    TO $1 
    WITH GRANT OPTION;

    ALTER DEFAULT PRIVILEGES
    GRANT ALL ON TABLES TO \"$1\" WITH GRANT OPTION;

    ALTER DEFAULT PRIVILEGES
    GRANT ALL ON SEQUENCES TO \"$1\" WITH GRANT OPTION;
    
    ALTER DEFAULT PRIVILEGES
    GRANT ALL ON FUNCTIONS TO \"$1\" WITH GRANT OPTION;

    ALTER DEFAULT PRIVILEGES
    GRANT USAGE ON TYPES TO \"$1\" WITH GRANT OPTION;

    " $2
}

function drop_schema() {
  echo "dropping schema $DEFAULT_SCHEMA"
  PGPASSWORD=$DEFAULT_PASSWORD psql \
    -U $DEFAULT_USER \
    -c "
    DROP SCHEMA IF EXISTS $DEFAULT_SCHEMA
    CASCADE
    " $DEFAULT_DB
}

function change_schema_owner() {
  echo "changing schema owner on $2 schema"
  PGPASSWORD=$DEFAULT_PASSWORD psql \
    -U $1 \
    -c "
    ALTER SCHEMA $2
    OWNER TO $1;
    " $3
}

function create_schema() {
  echo "creating schema $DEFAULT_SCHEMA"
  PGPASSWORD=$DEFAULT_PASSWORD psql \
    -U $DEFAULT_USER \
    -c "
    CREATE SCHEMA IF NOT EXISTS $DEFAULT_SCHEMA
    AUTHORIZATION $DEFAULT_USER
    " $DEFAULT_DB
}

function drop_connection() {
  echo "Dropping connection..."

  PGPASSWORD=$DEFAULT_PASSWORD psql \
    -U $DEFAULT_USER \
    -c "
    select pg_terminate_backend(pid) 
    from pg_stat_activity 
    where datname='$1';    
    " postgres
}

function set_connections() {
  PGPASSWORD=$DEFAULT_PASSWORD psql \
    -U $DEFAULT_USER \
    -c "
    ALTER DATABASE $1 
    WITH ALLOW_CONNECTIONS $2;
    " postgres
}

function enable_connections() {
  echo "Enabling connections"
  drop_connection $1
  set_connections $1 'true'
}

function disable_connections() {
  echo "Disabling connections"
  drop_connection $1
  set_connections $1 'false'
}

function rename_db() {
  echo "Dropping $1 connection..."
  PGPASSWORD=$DEFAULT_PASSWORD psql \
    -U $DEFAULT_USER \
    -c "
    ALTER DATABASE $1
    RENAME TO $2;
    " postgres
}

function dump_db() {
  echo "Dumping $DEFAULT_DB database."
  PGPASSWORD=$DEFAULT_PASSWORD pg_dump \
    -U $DEFAULT_USER \
    -f $DEFAULT_DUMP_FILE \
    -F c \
    $DEFAULT_DB
}

function restore_db() {
  local from=$DEFAULT_DB
  local to="$DEFAULT_DB"_new

  # prepare database for dump
  echo "Preparing database"
  disable_connections $to
  disable_connections "$from"_old
  drop_db $to
  drop_db "$from"_old
  create_db $to
  set_default_privileges $DEFAULT_USER $to
  change_schema_owner $DEFAULT_USER public $to

  # restore the db in new database
  echo "Restoring Databse"
  PGPASSWORD=$DEFAULT_PASSWORD pg_restore \
    -S $DEFAULT_USER \
    -d $to \
    --role=$DEFAULT_USER \
    --no-owner \
    --jobs=$(nproc --all) \
    $DEFAULT_DUMP_FILE

  echo "Flipping databases"
  disable_connections $to
  disable_connections $from

  rename_db $from "$from"_old
  rename_db $to $from

  drop_db "$from"_old
  enable_connections $from
}

function create_test_db() {
  disable_connections $DEFAULT_DB
  drop_db $DEFAULT_DB
  create_db $DEFAULT_DB
  set_default_privileges $DEFAULT_USER $DEFAULT_DB
  change_schema_owner $DEFAULT_USER public $DEFAULT_DB
}
