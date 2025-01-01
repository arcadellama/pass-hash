#!/usr/bin/env bash
# shellcheck disable=SC2004

# Copyright (C) 2024 Justin Teague <arcadellama@posteo.net>.
# This file is licensed under the GPLv2+.
# Please see LICENSE for more information.

readonly HASH_PROGRAM='pass-hash'
readonly HASH_VERSION='0.1'

HASH_ALGORITHM="${PASSWORD_STORE_HASH_ALGORITHM:-SHA512}"
HASH_DIR="${PASSWORD_STORE_HASH_DIR:-.pass-hash}"
HASH_ECHO="${PASSWORD_STORE_HASH_ECHO:-}"
HASH_INDEX_FILE="${PREFIX}/${HASH_DIR}/.hash-index"

#### Helper Functions ####
hash_die() {
  hash_reset_stty
	echo "[$HASH_PROGRAM] $*" >&2
	exit 1
}

hash_reset_stty() {
  [[ -t 0 ]] && stty $HASH_STTY >/dev/null 2>&1
}

hash_sum() {
  local bitdepth
  HASH_ALGORITHM="$(echo "$HASH_ALGORITHM" | tr "[:lower:]" "[:upper:]")"
  bitdepth="${HASH_ALGORITHM#SHA}"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a "$bitdepth" | cut -d' ' -f1
  elif
    command -v sha"${bitdepth}"sum >/dev/null 2>&1; then
    sha"${bitdepth}"sum | cut -d' ' -f1
  elif
    command -v sha"${bitdepth}" >/dev/null 2>&1; then
    sha"${bitdepth}" -r | cut -d' ' -f1
  else
    hash_die "Error: Unable to find a program to hash $HASH_ALGORITHM."
  fi
}

hash_secure_input() {
  if [[ -t 0 ]]; then
    trap 'hash_reset_stty' INT
		echo "Enter path to password and press Ctrl+D when finished:" >&2
    echo
    [[ "$HASH_ECHO" == 'true' ]] || stty -echo
  fi
  hash_sum | tr -d '\n'
  hash_reset_stty
}

#### Command Functions ####
hash_cmd_copy_move() {
  :
}

hash_cmd_delete() {
  :
}

hash_cmd_edit() {
  :
}

hash_cmd_find() {
  :
}

hash_cmd_generate() {
  :
}

hash_cmd_grep() {
  :
}

hash_cmd_usage() {
  cat <<-EOF
NAME
  $HASH_PROGRAM $HASH_VERSION

USAGE
  $PROGRAM hash [OPTIONS] [COMMAND] 

  In most cases, pass-hash acts as a shim for standard pass commands.
  Simply precede 'hash' to any commands seen in 'pass help.'

  Exceptions:
    - The hash index keeps a hashed version of your password path, a
      randomly (/dev/urandom) generated salt, and the algorithm each was
      hashed with. Meaning: your plaintext password 'key' is not kept, which
      does break some functionality from standard pass. Any function that
      requires knowing the plaintext of the key is modified, including
      'pass hash show' and 'pass hash find' without providing the path.

    - Unlike pass, pass-hash doesn't create separate directories for your 
      path. They are single hashed files stored in a separate subdirectory
      of the password store. Therefore, you can only copy, move, and delete
      hashed passwords at the password level, not at the directory level.

    - 'pass hash init' is a separate command from 'pass init', it's only job
      is to create and encrypt the hash index.


  Unique commands only found to pass-hash:
  hash import [path]: imports/moves passwords from the standard password
                      store into the hashed store

OPTIONS

  -e|--echo                       Turn on 'echo' for entering 
  -a|--algorithm <SHA algorithm>  SHA algorithm used for hashing entries
                                  and salts. Default: SHA512

ENVIRONMENT VARIABLES

  PASSWORD_STORE_HASH_ALGORITHM
    The SHA algorithm to use when hashing new files. Default: SHA512

  PASSWORD_STORE_HASH_DIR
    Sub-directory for the hashed password store. Default: .pass_hash

  PASSWORD_STORE_HASH_ECHO
    Boolean to echo back user input of paths / keys. Note: this only applies
    to the hash program. For standard pass commands, this will need to be set
    again.

EOF
}

hash_cmd_init() {
  :
}

hash_cmd_import() {
  :
}

hash_cmd_insert() {
  :
}

hash_cmd_copy_move() {
  :
}

hash_cmd_show() {
  :
}

# Set current stty if interactive terminal
[[ -t 0 ]] && HASH_STTY="$(stty -g)"

args=( "$@" )
# Parse pass-hash specific flags
while [ "$#" -gt 0 ]; do
  case "$1" in
    -e|--echo)
      HASH_ECHO='true'
      unset "args[-$#]"; shift
      ;;
    -a|--algorithm)
      HASH_ALGORITHM="${2:?"Error: missing algorithm."}"
      unset "args[-$#]"; shift
      unset "args[-$#]"; shift
      ;;
    -a*)
      HASH_ALGORITHM="${1#"-a"}"
      unset "args[-$#]"; shift
      ;;
    --algorithm=*)
      HASH_ALGORITHM="${1#"--algorithm="}"
      unset "args[-$#]"; shift
      ;;
    *)
      break
      ;;
  esac
done

set -- "${args[@]}"
case "$1" in
  copy|cp) shift;           hash_cmd_copy_move "copy" "$@" ;;
  delete|rm|remove) shift;  hash_cmd_delete "$@" ;;
  edit) shift;              hash_cmd_edit "$@" ;;
  find|search) shift;       hash_cmd_find "$@" ;;
  generate) shift;          hash_cmd_generate "$@" ;;
  grep) shift;              hash_cmd_grep "$@" ;;
  help|--help) shift;       hash_cmd_usage ;;
  init) shift;              hash_cmd_init "$@" ;;
  import) shift;            hash_cmd_import "$@" ;;
  insert|add) shift;        hash_cmd_insert "$@" ;;
  rename|mv) shift;         hash_cmd_copy_move "move" "$@" ;;
  show|ls|list) shift;      hash_cmd_show "$@" ;;
  *)                        hash_cmd_show "$@" ;;
esac

hash_reset_stty
exit 0
