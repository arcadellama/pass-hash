#!/usr/bin/env bash

test_description='Sanity checks'
cd "$(dirname "$0")"
. ./setup.sh

test_expect_success 'Make sure we can run pass' '
	"$PASS" --help | grep "pass: the standard unix password manager"
'

test_expect_success 'Make sure we can run pass hash' '
	"$PASS" hash --help | grep "pass-hash"
'

test_expect_success 'Make sure we can initialize our test store' '
	"$PASS" init $KEY1 &&
	[[ -e "$PASSWORD_STORE_DIR/.gpg-id" ]] &&
	[[ $(cat "$PASSWORD_STORE_DIR/.gpg-id") == "$KEY1" ]]
'

test_expect_success 'Make sure we can initialize our pass-hash test store' '
	"$PASS" hash init $KEY1 &&
	[[ -e "$PASSWORD_STORE_DIR/.pass-hash" ]] &&
	[[ -e "$PASSWORD_STORE_DIR/.pass-hash/.hash-index.gpg" ]]
'

test_done
