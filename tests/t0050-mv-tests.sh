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

test_expect_success 'Git is consistent' '
	[[ -z $(git status --porcelain 2>&1) ]]
'

test_done
