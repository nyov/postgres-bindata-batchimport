postgres-bindata-batchimport
----------------------------

PostgreSQL batch-importing binary files, from disk to database table.
Using the [Large Objects][1] interface.
(PostgreSQL 9.3+)

The shell scripts `pg-*-batchimport-cs.sh` and `pg-*-batchimport-ss.sh`
are very similar.
The former (*client-side*) can be used with a remote database cluster and only
uses `psql`-local functions, while the latter (*server-side*) executes commands
on the db cluster and thus requires cluster-local file access (read permission)
by the postgres user.

The server-local variant is on average 50% faster than the client-side (remote)
version (even with a local cluster), since the client-side code must execute a
large-object import and `UPDATE` statement for each file.
With a remote cluster, bandwidth limitations for the file uploads can further
impact the execution speed.


##### Usage #####

Importing files as Large Objects only:
```sh
./pg-lo-batchimport-cs.sh    <databasename> <source-directory> [<tablename>]
./pg-lo-batchimport-ss.sh    <databasename> <source-directory> [<tablename>]
```
Using large objects gives all the gimmicks that the [Large Objects][1]
file-like interface supports (such as seeking). Reference them by the table's
`oid` column.

Converting files into BYTEA table rows after import:
```sh
./pg-bytea-batchimport-cs.sh <databasename> <source-directory> [<tablename>]
./pg-bytea-batchimport-ss.sh <databasename> <source-directory> [<tablename>]
```
The `source-directory` will be walked recursively, using `find`, by default.
`find` supports many modifier options to grab files selectively, e.g. limited
to depth level, or files newer than `$last-run` minutes, for recurring jobs.

##### Example #####

```sh
#!/bin/sh

# Generate 20 files with some text, or use your own:
mkdir /tmp/randomtext
for OF in `seq 101 120`; do curl -s http://metaphorpsum.com/paragraphs/5/5 > /tmp/randomtext/${OF}; done

# DB to use, possibly replace 'postgres' with an existing test-database
DB="postgres"
TABLE="tmp_docs"

# Run script
./pg-bytea-batchimport-cs.sh $DB /tmp/randomtext $TABLE
# (or) Server-side version; faster, but requires a local db cluster
#./pg-bytea-batchimport-ss.sh $DB /tmp/randomtext $TABLE

# Verify contents in db; should count 20 rows
psql -c "SELECT count(*) FROM $TABLE" $DB
psql -c "SELECT file_name, encode(doc::bytea, 'escape')::text AS data FROM $TABLE LIMIT 1" $DB

# clean up
rm -r /tmp/randomtext
psql -c "DROP TABLE $TABLE" $DB
unset TABLE
unset DB
```
(This code snippet can be pasted into a file and executed as a shell script,
 as is.)

##### Notes & Caveats #####

If the script aborts before the created large objects have been cleaned up
and the table is then dropped without unlinking them, orphaned objects stay
around. The `\lo_list` (local to database) command can help finding them.
If the current DB contains no valid objects beside the failed import, the
nuke-em command is `SELECT lo_unlink(oid) FROM pg_largeobject_metadata;`.

Because the workflow used in the `pg-bytea-batchimport-*.sh` scripts makes a
round-trip through large-objects-storage land, the DB cluster may use up to
double the space of the source file directory, for the runtime duration of the
script.

Depending on the type of files, this may not be true, however; with
text-files I've seen a compression ratio of 2 GiB raw on-disk to 400 MiB
in-db of the same data. Which means even with two copies, the database was
using less storage than the source directory data.

---

![Public Domain Icon](https://upload.wikimedia.org/wikipedia/commons/thumb/6/62/PD-icon.svg/16px-PD-icon.svg.png)
Public Domain. No warranties of any kind, express or implied.

Further information and alternative methods to handle data importing in
PostgreSQL can be found in the PDF presentation
[PGOpen2018_data_loading.pdf][2], which inspired this code; and on
[StackOverflow][3].

  [1]: https://www.postgresql.org/docs/current/largeobjects.html
  [2]: https://www.postgis.us/presentations/PGOpen2018_data_loading.pdf
  [3]: https://dba.stackexchange.com/q/253425
