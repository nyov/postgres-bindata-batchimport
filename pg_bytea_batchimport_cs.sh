#!/bin/sh
#
# PostgreSQL batch-importing binary files, from disk to database table.
# - psql client-side file paths -
#
# by nyov, 2019
# Public Domain
#
# Run as
# ./this-script.sh <databasename> <source-directory> [<tablename>]
#

DATABASE="${1}"
FILEPATH="${2}"
TBLENAME="${3:-tmp_docs}"

# add additional options to `find` files more selectively
# (e.g. limited to depth level, or newer than $last-run minutes)
EVAL_CMD="find ${FILEPATH} -type f"
# fallback: `ls`, may not create desired output, will not work with many files
#EVAL_CMD="ls ${FILEPATH}/* -R"


if [ -z "${DATABASE}" ] || [ -z "${FILEPATH}" ]
then
	echo "Missing argument"
	exit 1
fi

TMPFILE="`mktemp`_loadscript.psql"

SQL="CREATE TABLE \"${TBLENAME}\" (
	file_name TEXT,
	doc BYTEA,
	doc_oid OID
);"
psql -c "${SQL}" "${DATABASE}"

SQL="\copy \"${TBLENAME}\" (file_name) FROM PROGRAM '${EVAL_CMD}' WITH (FORMAT csv, DELIMITER '|')"
psql -c "${SQL}" "${DATABASE}"

# Remove the directory name itself, if any (from `ls / -R` output)
SQL="DELETE FROM \"${TBLENAME}\" WHERE file_name LIKE '${FILEPATH}%:'"
psql -c "${SQL}" "${DATABASE}"

# Generate a loading script with psql instructions
SQL="SELECT '\lo_import ' || quote_literal(replace(file_name, '\', '/'))
|| '
UPDATE \"${TBLENAME}\" SET doc_oid = :LASTOID
	WHERE file_name = ' || quote_literal(file_name) || ';'
	FROM \"${TBLENAME}\";
"
psql -o "${TMPFILE}" -t -c '\x off' -A -c "${SQL}" "${DATABASE}"
echo "Generated ${TMPFILE}"

# CLIENT-SIDE data loading (slow for many files, runs an UPDATE for each file)
# - execute generated psql instructions -
# db=# \i /tmp/loadscript.psql
echo "Loading data..."
psql -q -c '\timing off' -f "${TMPFILE}" "${DATABASE}"
if [ $? -eq 0 ]; then
	echo "Cleaning up ${TMPFILE}"
	rm "${TMPFILE}"
else
	echo "PSQL execution failed on importing. Aborting."
	echo "Check the generated script for correctness: ${TMPFILE}"
	exit 1
fi

# Loading large-object data into BYTEA table column
SQL="UPDATE \"${TBLENAME}\" SET doc = lo_get(doc_oid)"
psql -c "${SQL}" "${DATABASE}"

# Remove large-object stored copies
SQL="SELECT count(lo_unlink(o.oid)) AS lo_unlinked FROM pg_largeobject_metadata AS o WHERE o.oid IN (SELECT doc_oid FROM \"${TBLENAME}\")"
psql -c "${SQL}" "${DATABASE}"

# Build index on file_name column
SQL="ALTER TABLE \"${TBLENAME}\" ADD UNIQUE (file_name)"
psql -c "${SQL}" "${DATABASE}"

# Drop now useless doc_oid column
SQL="ALTER TABLE \"${TBLENAME}\" DROP COLUMN doc_oid"
psql -c "${SQL}" "${DATABASE}"
