#!/usr/bin/env bash

test_description='Test mv command'
cd "$(dirname "$0")"
. ./setup.sh

INITIAL_PASSWORD="bla bla bla will we make it!!"

test_expect_success 'Basic move command' '
	"$PASS" init $KEY1 &&
	"$PASS" git init &&
	"$PASS" hash init &&
	"$PASS" hash insert -e cred1 <<<"$INITIAL_PASSWORD" &&
	"$PASS" hash mv cred1 cred2 &&
  "$PASS" hash show cred1 || "$PASS" hash show cred2
'
test_expect_success 'Basic move command via stdin' '
  "$PASS" hash insert -e <<< "$(printf "cred3\n%s\n" "$INITIAL_PASSWORD" )" &&
  "$PASS" hash mv <<< "$(echo "cred3 cred4")" &&
  "$PASS" hash show cred3 || "$PASS" hash show cred4
'

test_expect_success 'Git is consistent' '
	[[ -z $(git status --porcelain 2>&1) ]]
'

test_done
