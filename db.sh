. ./core.sh

export DEFAULT_DB=hospitalinsights
export DEFAULT_DUMP_FILE="pg_dump/$DEFAULT_DB.pg"
restore_db
