#!/bin/sh
#
# PostgreSQL batch-importing binary files, from disk to database table.
# - server-side file paths -
#
# by nyov, 2019
# Public Domain
#
# Run as
# ./pg-lo-batchimport-ss.sh <databasename> <source-directory> [<tablename>]
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
	doc_oid OID
);"
psql -c "${SQL}" "${DATABASE}"

SQL="COPY \"${TBLENAME}\" (file_name) FROM PROGRAM '${EVAL_CMD}' WITH (FORMAT csv, DELIMITER '|')"
psql -c "${SQL}" "${DATABASE}"

# SERVER-SIDE data import
SQL="UPDATE tmp_docs SET doc_oid = lo_import(file_name)"
psql -c "${SQL}" "${DATABASE}"

# Build index on file_name column
SQL="ALTER TABLE \"${TBLENAME}\" ADD UNIQUE (file_name)"
psql -c "${SQL}" "${DATABASE}"
