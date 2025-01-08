#!/usr/bin/env bash

test_description='Test insert'
cd "$(dirname "$0")"
. ./setup.sh

test_expect_success 'Test "insert" command' '
	"$PASS" init $KEY1 &&
	"$PASS" hash init &&
	echo "Hello world" | "$PASS" hash insert -e cred1 &&
	[[ $("$PASS" hash show cred1) == "Hello world" ]]
'

test_expect_success 'Test "insert" command all via standard in' '
  printf "cred2\nHello world\n" | "$PASS" hash insert -e &&
	[[ $("$PASS" hash show cred2) == "Hello world" ]]
'

test_done
