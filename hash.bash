#!/usr/bin/env bash
# shellcheck disable=SC2004

# Copyright (C) 2024 Justin Teague <arcadellama@posteo.net>.
# This file is licensed under the GPLv2+.
# Please see LICENSE for more information.

readonly HASH_PROGRAM='pass-hash'
readonly HASH_VERSION='0.1'

HASH_ALGORITHM="${PASSWORD_STORE_HASH_ALGORITHM:-SHA512}"
HASH_DIR="${PASSWORD_STORE_HASH_DIR:-.pass-hash}"
HASH_INDEX_FILE="${PREFIX}/${HASH_DIR}/.hash-index"
HASH_ECHO="${PASSWORD_STORE_HASH_ECHO:-}"

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
		echo "Enter $1 and press Ctrl+D when finished:" >&2
    echo
    [[ "$HASH_ECHO" == 'true' ]] || stty -echo
  fi
  { hash_sum | tr -d '\n'; printf \\n; }
  hash_reset_stty
}

hash_salt() {
  head -4096 | hash_sum
}

hash_make_entry() {
  printf '%s\t%s\t%s\n' "$1" "$(hash_salt)" "$HASH_ALGORITHM"
}

hash_index_add() {
  { cmd_show "$HASH_INDEX_FILE"; echo "$1"; } | \
    cmd_insert -f -m "$HASH_INDEX_FILE" >/dev/null
}

hash_index_delete() {
  cmd_show "$HASH_INDEX_FILE" | grep -v "^$1	" | \
    cmd_insert -f -m "$HASH_INDEX_FILE" >/dev/null
}

hash_index_get_entry() {
  cmd_show "$HASH_INDEX_FILE" | grep "^$1	" || \
    hash_die "Error: path not found in hash index."
}

hash_get_salted_path() {
  local old_ifs old_algo
  old_ifs=$IFS
  IFS=$'\t'
  old_algo="$HASH_ALGORITHM"
  HASH_ALGORITHM="$3"
  echo "${1}${2}" | hash_sum 
  HASH_ALGORITHM="$old_algo"
  IFS=$old_ifs
} 

#### Command Functions ####
hash_cmd_copy_move() {
  # copy|move [--force, -f] old-path new-path
  [[ -f "$HASH_INDEX_FILE" ]] || hash_die "Error: pass-hash index not found."
  local args cmd old_path new_path new_entry
  args=( "$@" )
  while [ "$#" -gt 0 ]; do
    case "$1" in
      copy|move) cmd="$1"; shift ;;
      -*) shift ;;
      *)
        old_path="$(echo "${args[-$#]}" | hash_sum)"
        new_path="$(echo "${args[-$(($#-1))]}" | hash_sum)"
        unset "${args[-$#]}" "${args[-$(($#-1))]}"
        break
        ;;
    esac
  done

  if [[ -z "$old_path" ]] && [[ -z "$new_path" ]]; then
    old_path="$(hash_secure_input "current path to copy/move from")"
    new_path="$(hash_secure_input "new path to copy/move to")"
  else
    cmd_copy_move "${args[@]}"
  fi 

  new_entry="$(hash_make_entry "$new_path")"

  cmd_copy_move "${args[@]}" \
    "$HASH_DIR/$(hash_index_get_entry "$old_path" | hash_get_salted_path)" \
    "$HASH_DIR/$(echo "$new_entry" | hash_get_salted_path)"

  [[ "$cmd" == "move" ]] && hash_index_delete "$old_path"
  hash_index_add "$new_entry"
}

hash_cmd_delete() {
  # [ --recursive, -r ] [ --force, -f ] pass-name
  [[ -f "$HASH_INDEX_FILE" ]] || hash_die "Error: pass-hash index not found."
  local args path new_entry
  args=( "$@" )
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -*) shift ;;
      *)  path="$(echo "$1" | hash_sum)"; unset "args[-$#]" ;;
    esac
  done

  [[ -n "$path" ]] || path="$(hash_secure_input "password name")"
  
  cmd_delete "${args[$@]}" \
    "$HASH_DIR/$(hash_index_get_entry "$path" | hash_get_salted_path)"
  hash_index_delete "$path"
}

hash_cmd_edit() {
  # pass-name
  [[ -f "$HASH_INDEX_FILE" ]] || hash_die "Error: pass-hash index not found."
  local path new_entry
  if [ "$#" -gt 0 ]; then
    path="$(echo "$1" | hash_sum)"
  else
    path="$(hash_secure_input "password name")"
  fi

  if ! cmd_show "$HASH_INDEX_FILE" | grep -q "$^$path	"; then
    new_entry="$(hash_make_entry "$path")"
    cmd_edit "$(echo "$new_entry" | hash_get_salted_path)"
    hash_index_add_entry "$new_entry"
  else
    cmd_edit "$(hash_index_get_entry "$path" | hash_get_salted_path)"
  fi
}

hash_cmd_find() {
  hash_die "'find' command does not work with pass-hash store."
}

hash_cmd_generate() {
  # [ --no-symbols, -n ] [ --clip, -c ] [ --in-place,
  #     -i | --force, -f ] pass-name [pass-length]
  [[ -f "$HASH_INDEX_FILE" ]] || hash_die "Error: pass-hash index not found."
  local args path len
  args=( "$@" )
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -*) shift ;;
      *)
        path="$(echo "$1" | hash_sum)"
        unset "args[-$#]"
        len="${2:-}"
        [[ -n "$len" ]] && unset "args[-1]"
        break
        ;;
    esac
  done

  if [ -z "$path" ];
    path="$(hash_secure_input "password name")"
    [[ -n "$len" ]] || len="$(hash_secure_input "password length")"
  fi
  if ! cmd_show "$HASH_INDEX_FILE" | grep -q "$^$path	"; then
    new_entry="$(hash_make_entry "$path")"
    cmd_generate "${args[@]}" "$(echo "$new_entry" | hash_get_salted_path)"
    hash_index_add_entry "$new_entry"
  else
    cmd_generate "${args[@]}" \
      "$(hash_index_get_entry "$path" | hash_get_salted_path)"
  fi


}

hash_cmd_grep() {
  cmd_grep "$@"
}

hash_cmd_usage() {
  cat <<-EOF
NAME
  $HASH_PROGRAM $HASH_VERSION

USAGE
  $PROGRAM hash [-a|--algorithm "<name>:<command>"] [-e|--echo] [COMMAND]

OPTIONS
  -a|--algorithm "<name:command>" Set the algorithm used in hashing password  
                                  names and salts. Argument is a quoted string
                                  with the name of the algorithm and the
                                  command used to use it separated by a ':'.
                                  This script assumes the algorithm will be
                                  a SHA hash. If the command is ommitted,
                                  a suitable command will attempt to be found.
                                  This overrides the environment variable,
                                  PASSWORD_STORE_HASH_ALGORITHM.
                                  See ENVIRONMENT VARIALBLES for more info.

  -e|--echo                       Turn on local echo for entry of password
                                  names. Only applies to the password name 
                                  functionality of pass-hash. To also enable
                                  echo on pass (e.g., 'pass hash insert'), 
                                  this flag will need to be passed again.

SYNOPSIS
  In most cases, pass-hash acts as a shim for standard pass commands.
  Simply precede 'hash' to any commands seen in 'pass help.'

  Unique to pass-hash is the password name, used as a path in standard pass,
  can be passed via standard in (STDIN). In cases where pass expects input
  on standard in (e.g., pass insert), separate the input by a new line. In
  the case of 'pass hash insert,' the first line of standard input would be
  the password name, the second line of standard input would be the password.

  This is the recommended way to use the pass-hash extension, as the assumed
  security model is to keep the name of the password obfuscated (whereas the
  model for standard 'pass' is to only encrypt the password itself). However,
  to keep backwards compatibility, pass-hash will also accept password names 
  as arguments, but this is not recommended.

  Other Exceptions:
    - The hash index keeps a hashed version of your password name, a
      randomly (/dev/urandom) generated salt, and the algorithm each was
      hashed with. Meaning: your plaintext password name is not kept, which
      does break some functionality from standard pass. Any function that
      requires knowing the plaintext of the name will not work as expected if
      the full password name is not provided, including 'pass hash show' and
      'pass hash find'.

    - Unlike 'pass', you can only copy, move, and delete hashed by it's
      complete password name, as pass-hash doesn't create a full path of 
      separate directories for the password name. They are single hashed files
      stored in a separate subdirectory set by PASSWORD_STORE_HASH_DIR.

    - 'pass hash init' is a separate command from 'pass init', it's only job
      is to create and encrypt the hash index.

ENVIRONMENT VARIABLES

  PASSWORD_STORE_HASH_ALGORITHM
    Default: "SHA512"
    A ':' separated string with the first part being the name of the algorithm
    followed by the command used to program used. The program must accept piped
    input via standard in and output the hash as the first argument.
    In the case of a BSD-style program like sha512, this would be set to
    "SHA512:sha512 -r". If the second half of the ':' is ommitted, the script
    will attempt to find the right command and will exit with an error if not
    found.

  PASSWORD_STORE_HASH_DIR
    Sub-directory for the hashed password store. Default: .pass_hash

  PASSWORD_STORE_HASH_ECHO
    Boolean to echo back user input of password names. Note: this only applies
    to the hash extension. For standard pass commands, this will need to be set
    again.

EOF
}

hash_cmd_init() {
  [[ -f "$HASH_INDEX_FILE" ]] && \
    hash_die "Error: $HASH_INDEX_FILE already exists."

  # Create and encrypt index file
  echo "# $HASH_PROGRAM -- $HASH_VERSION" | \
    cmd_insert -f "$HASH_DIR/$(basename -- "$HASH_INDEX_FILE")" > /dev/null
}

hash_cmd_insert() {
  # [ --echo, -e | --multiline, -m ] [ --force, -f ] pass-name
  [[ -f "$HASH_INDEX_FILE" ]] || hash_die "Error: run 'pass hash init' first."
  local args path new_entry
  args=( "$@" )
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -*) shift ;;
      *)  path="$(echo "$1" | hash_sum)"; unset "args[-$#]" ;;
    esac
  done

  path="${path:-"$(hash_secure_input "password name")"}"
  new_entry="$(hash_make_entry "$path")"
  cmd_insert -f -m "${args[@]}" "$HASH_DIR/$(echo "$new_entry" | cut -f1)"
  hash_index_add "$new_entry"
}

hash_cmd_show() {
  [[ -f "$HASH_INDEX_FILE" ]] || hash_die "Error: pass-hash index not found."
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
