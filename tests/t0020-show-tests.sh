#!/usr/bin/env bash

test_description='Test show'
cd "$(dirname "$0")"
. ./setup.sh

test_expect_success 'Test "show" command' '
	"$PASS" init $KEY1 &&
	"$PASS" hash init $KEY1 &&
	"$PASS" hash generate cred1 20 &&
	"$PASS" hash show cred1
'

test_expect_success 'Test "show" command via stdin' '
	"$PASS" init $KEY1 &&
	"$PASS" hash init $KEY1 &&
	printf "cred2\n20\n" | "$PASS" hash generate &&
	echo "cred2" | "$PASS" hash show
'

test_expect_success 'Test "show" command with spaces' '
	"$PASS" hash insert -e "I am a cred with lots of spaces"<<<"BLAH!!" &&
	[[ $("$PASS" hash show "I am a cred with lots of spaces") == "BLAH!!" ]]
'

test_expect_success 'Test "show" command with unicode' '
	"$PASS" hash generate 🏠 &&
	"$PASS" hash show '🏠'
'

test_expect_success 'Test "show" of nonexistant password' '
	test_must_fail "$PASS" hash show cred99
'

test_done
