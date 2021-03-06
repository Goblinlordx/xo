#!/bin/bash

# NOTE: please use xo/contrib/orcreate.sh to create a booktest user and database first
# also, consider using xo/contrib/orstart.sh to start your docker instance

DBUSER=booktest
DBPASS=booktest
DBHOST=$(docker port orcl 1521)
DBNAME=xe.oracle.docker

SP=$DBUSER/$DBPASS@$DBHOST/$DBNAME
DB=oracle://$DBUSER:$DBPASS@$DBHOST/$DBNAME

EXTRA=$1

SRC=$(realpath $(cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd ))

XOBIN=$(which xo)
if [ -e $SRC/../../../xo ]; then
  XOBIN=$SRC/../../../xo
fi

DEST=$SRC/models

set -x

mkdir -p $DEST
rm -f $DEST/*.go
rm -f $SRC/oracle

sqlplus -S $SP <<< 'DROP INDEX books_title_idx;'
sqlplus -S $SP <<< 'DROP INDEX authors_name_idx;'
sqlplus -S $SP <<< 'DROP TABLE books CASCADE CONSTRAINTS;'
sqlplus -S $SP <<< 'DROP TABLE authors CASCADE CONSTRAINTS;'

sqlplus -S $SP << 'ENDSQL'
CREATE TABLE authors (
  author_id integer GENERATED BY DEFAULT ON NULL AS IDENTITY PRIMARY KEY,
  name nvarchar2(255) DEFAULT '' NOT NULL
);

CREATE INDEX authors_name_idx ON authors(name);

CREATE TABLE books (
  book_id integer GENERATED BY DEFAULT ON NULL AS IDENTITY PRIMARY KEY,
  author_id integer REFERENCES authors(author_id) NOT NULL,
  isbn nvarchar2(255) DEFAULT '' UNIQUE NOT NULL,
  title nvarchar2(255) DEFAULT '' NOT NULL,
  year integer DEFAULT 2000 NOT NULL,
  available timestamp with time zone NOT NULL,
  tags nvarchar2(255) DEFAULT '' NOT NULL
);

CREATE INDEX books_title_idx ON books(title, year);

ENDSQL

$XOBIN $DB -o $SRC/models $EXTRA

$XOBIN $DB -N -M -B -T AuthorBookResult --query-type-comment='AuthorBookResult is the result of a search.' -o $SRC/models $EXTRA << ENDSQL
SELECT
  a.author_id AS author_id,
  a.name AS author_name,
  b.book_id AS book_id,
  b.isbn AS book_isbn,
  b.title AS book_title,
  b.tags AS book_tags
FROM books b
JOIN authors a ON a.author_id = b.author_id
WHERE b.tags LIKE '%' || %%tags string%% || '%'
ENDSQL

pushd $SRC &> /dev/null

go build
./oracle -host $DBHOST -db $DBNAME $EXTRA

popd &> /dev/null

sqlplus -S $SP << ENDSQL
set linesize 120;
set wrap off;
select book_id, author_id, substr(isbn,1,4) AS ISBN, substr(title,1,16) AS TITLE, year, substr(tags,1,20) AS TAGS, substr(available,1,15) as AVAILABLE from books;
ENDSQL
