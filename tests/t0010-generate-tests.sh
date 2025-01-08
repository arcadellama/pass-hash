#!/usr/bin/env bash

test_description='Test generate'
cd "$(dirname "$0")"
. ./setup.sh

test_expect_success 'Test "hash generate" command' '
	"$PASS" init $KEY1 &&
  "$PASS" hash init &&
	"$PASS" hash generate cred 19 &&
	[[ $("$PASS" hash show cred | wc -m) -eq 20 ]]
'

test_expect_success 'Test replacement of first line' '
	"$PASS" hash insert -m cred2 <<<"$(printf "this is a big\\npassword\\nwith\\nmany\\nlines\\nin it bla bla")" &&
	"$PASS" hash generate -i cred2 23 &&
	[[ $("$PASS" hash show cred2) == "$(printf "%s\\npassword\\nwith\\nmany\\nlines\\nin it bla bla" "$("$PASS" hash show cred2 | head -n 1)")" ]]
'

test_done
