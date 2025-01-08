#!/usr/bin/env bash

test_description='Test rm'
cd "$(dirname "$0")"
. ./setup.sh

test_expect_success 'Test "rm" command' '
	"$PASS" init $KEY1 &&
	"$PASS" hash init &&
	"$PASS" hash generate cred1 43 &&
	"$PASS" hash rm cred1 && 
  "$PASS" hash show cred1 || true
'

test_expect_success 'Test "rm" command with spaces' '
	"$PASS" hash generate "hello i have spaces" 43 &&
	"$PASS" show "hello i have spaces" &&
	"$PASS" hash rm "hello i have spaces" && 
	"$PASS" show "hello i have spaces" || true
'

test_expect_success 'Test "rm" of non-existent password' '
	test_must_fail "$PASS" hash rm does-not-exist
'

test_done
