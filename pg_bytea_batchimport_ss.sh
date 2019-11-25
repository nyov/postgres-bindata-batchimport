#!/bin/sh
#
# PostgreSQL batch-importing binary files, from disk to database table.
# - server-side file paths -
#
# by nyov, 2019
# Public Domain
#
# Run as
# ./this-script.sh <databasename> <source-directory> [<tablename>]
#
# Note: <source-directory> will be expanded to an absolute path,
#       which must be readable by the postgres cluster user.
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

SQL="CREATE TABLE \"${TBLENAME}\" (
	file_name TEXT,
	doc BYTEA,
	doc_oid OID
);"
psql -c "${SQL}" "${DATABASE}"

SQL="COPY \"${TBLENAME}\" (file_name) FROM PROGRAM '${EVAL_CMD}' WITH (FORMAT csv, DELIMITER '|')"
psql -c "${SQL}" "${DATABASE}"

# Remove the directory name itself, if any (from `ls / -R` output)
SQL="DELETE FROM \"${TBLENAME}\" WHERE file_name LIKE '${FILEPATH}%:'"
psql -c "${SQL}" "${DATABASE}"

# SERVER-SIDE data import
SQL="UPDATE tmp_docs SET doc_oid = lo_import(file_name)"
psql -c "${SQL}" "${DATABASE}"

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
