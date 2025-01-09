#!/usr/bin/env bash

test_description='Grep check'
cd "$(dirname "$0")"
. ./setup.sh

test_expect_success 'Make sure grep prints normal lines' '
	"$PASS" init $KEY1 && "$PASS" hash init $KEY1 &&
	"$PASS" hash insert -e blah1 <<<"hello" &&
	"$PASS" hash insert -e blah2 <<<"my name is" &&
	"$PASS" hash insert -e folder/blah3 <<<"I hate computers" &&
	"$PASS" hash insert -e blah4 <<<"me too!" &&
	"$PASS" hash insert -e folder/where/blah5 <<<"They are hell" &&
	results="$("$PASS" hash grep hell)" &&
	[[ $(wc -l <<<"$results") -eq 4 ]] &&
	grep -q "They are" <<<"$results"
'

test_expect_success 'Test passing the "-i" option to grep' '
	"$PASS" init $KEY1 && "$PASS" hash init $KEY1 &&
	"$PASS" hash insert -e blah6 <<<"I wonder..." &&
	"$PASS" hash insert -e blah7 <<<"Will it ignore" &&
	"$PASS" hash insert -e blah8 <<<"case when searching?" &&
	"$PASS" hash insert -e folder/blah9 <<<"Yes, it does. Wonderful!" &&
	results="$("$PASS" hash grep -i wonder)" &&
	[[ $(wc -l <<<"$results") -eq 4 ]]
'

test_done
