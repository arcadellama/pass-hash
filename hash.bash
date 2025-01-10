#!/usr/bin/env bash
#
# pass-hash: a Password Store (https://passwordstore.org) extension.
#
# Copyright (C) 2024 Justin Teague <arcadellama@posteo.net>.
# All rights reserved.
# This file is licensed under the GPLv3+. See COPYING for more information.


readonly HASH_PROGRAM='pass-hash'
readonly HASH_VERSION='0.2'

HASH_ALGORITHM="${PASSWORD_STORE_HASH_ALGORITHM:-SHA512}"
HASH_DIR="${PASSWORD_STORE_HASH_DIR:-.pass-hash}"
HASH_ECHO="${PASSWORD_STORE_HASH_ECHO:-}"

#### General Functions ####
hash_die() {
	echo "[$HASH_PROGRAM] $*" >&2
	exit 1
}

hash_sum() {
  # A default of SHA is assumed, but easily overriden in the future with
  # a new case entry. Testing needs to be done across different POSIX systems
  # to ensure these SHA commands function correctly.
  #
  # This deviates a bit from how 'pass' handles such situations, like in tmpdir
  # in that it inefficiently processes some constants like which programs are
  # on the system each time it is called. However, because there can
  # conceivably be a mixed use of algorithms in situations with older index
  # entries, a re-check of commands would be neccessary anyways. So, a cleaner
  # and more readable code was opted for a slight increase in efficiency.
  #
  # Most importantly, the alternate command must still output the 'hash'
  # as the first entry.

  local algo_command algo_bit

  case "$HASH_ALGORITHM" in
    *:*)
      algo_command="${HASH_ALGORITHM#*:}"
      $algo_command | cut -d' ' -f1 || exit 1
      ;;
    SHA*|sha*)
      HASH_ALGORITHM="$(echo "$HASH_ALGORITHM" | tr '[:lower:]' '[:upper:]')"
      algo_bit="${HASH_ALGORITHM#SHA}"
      if command -v shasum >/dev/null 2>&1; then
        shasum -a "$algo_bit" | cut -d' ' -f1 || exit 1
      elif
        command -v sha"${algo_bit}"sum >/dev/null 2>&1; then
        sha"${algo_bit}"sum | cut -d' ' -f1 || exit 1
      elif
        command -v sha"${algo_bit}" >/dev/null 2>&1; then
        sha"${algo_bit}" -r | cut -d' ' -f1 || exit 1
      else
        hash_die "Error: Unable to find a program to hash $HASH_ALGORITHM."
      fi
      ;;
    *)
      hash_die "Error: unknown hash algorithm ($HASH_ALGORITHM)"
  esac
}

hash_salt() {
  # Updating the first half of this pipe will not break future functionality.
  # Using 4096 lines of /dev/urandom is probably not necessary.
  head -4096 < /dev/urandom | hash_sum
}

hash_make_entry() {
  # TAB Delineated table
  # <hashed password name>  | <hashed salt> | <algorithm:command>
  printf '%s\t%s\t%s\n' "$1" "$(hash_salt)" "$HASH_ALGORITHM"
}

hash_get_salted_path() {
  # Hashes the first two entries of the selected tab delineated line with the 
  # algorithm in the third entry.
  local old_ifs old_algo name_hash salt_hash entry_algo
  old_ifs=$IFS
  old_algo="$HASH_ALGORITHM"

  IFS=$'\t' read -r name_hash salt_hash entry_algo || exit 1
  HASH_ALGORITHM="$entry_algo"
  echo "${name_hash}${salt_hash}" | hash_sum 

  HASH_ALGORITHM="$old_algo"
  IFS=$old_ifs
} 

#### Index Functions ####
hash_index_check() {
  if [ -f "${HASH_INDEX_FILE}.gpg" ] || [ -f "${HASH_INDEX_FILE}.age" ]; then
    return 0
  else
    return 1
  fi
}

hash_index_update() {
  # It is important that this command is only run after the 'pass' function
  # successfully makes updates to the system so that the index can stay in
  # sync.
  local index_file
  index_file="${HASH_DIR}/$(basename -- "$HASH_INDEX_FILE")"

  [[ -n "${1:-}" ]] || hash_die "Error: password name/path cannot be empty."

  if hash_index_get_entry "$(echo "$1" | cut -f1)" >/dev/null; then
    hash_index_delete "$(echo "$1" | cut -f1)"
  fi

  { cmd_show "$index_file"; echo "$1"; } | \
    cmd_insert -f -m "$index_file" | grep -v 'Enter contents of.*'
}

hash_index_delete() {
  # This read loop a very inefficient way to replace a single line in a file 
  # and could be replaced with a simple 'grep -v "^$1	"'. However, by using the
  # built-in read there is (probably?) a minor reduction in exposing a secret
  # by not needing to pass the non-salted hash of the pass-name
  # to an external program as an argument.
  local line index_file
  index_file="${HASH_DIR}/$(basename -- "$HASH_INDEX_FILE")"
  [[ -n "${1:-}" ]] || hash_die "Error: password name/path cannot be empty."
  cmd_show "$index_file" | \
    while read -r line; do
      case "$line" in
        "$1"\	*) continue ;;
        *) echo "$line"   ;;
      esac
    done | cmd_insert -f -m "$index_file" | grep -v 'Enter contents of.*'

}

hash_index_get_entry() {
  # This could be replaced with a simple one-line to 'grep "^$1	"', however
  # this more inefficiently eliminates the need to call an external command
  # with the non-salted hash of the pass-name, which might reduce the
  # possiblity of exposing a secret.
  local line index_file
  index_file="${HASH_DIR}/$(basename -- "${HASH_INDEX_FILE}")"

  [[ -n "${1:-}" ]] || hash_die "Error: password name/path cannot be empty."

  while read -r line; do
    case "$line" in "$1"\	*) echo "$line"; return 0 ;; esac
  done < <(cmd_show "$index_file")
  return 1
}

#### Pass Command Shim Functions ####
hash_cmd_double_field() {
  local cmd args msg field1 field2
  hash_index_check || hash_die "Error: no pass-hash index."


  cmd="$1" # copy|move|generate

  case "$cmd" in
    copy|move)
      msg="<old password name> <new password name>"
      ;;
    generate)
      msg="<password name> <password length (optional)>"
      shift # unset 'generate' from arguments
      ;;
  esac

  args=( "$@" )
  # find if path is an argument
  while [ "$#" -gt 0 ]; do
    case "$1" in
      copy|move) shift ;;
      -*) shift ;;
      *)
        if [ -n "$field1" ]; then
          field2="$1"; unset "args[-$#]" 
        else
          field1="$1"; unset "args[-$#]" 
        fi
        shift
        ;;
    esac
  done

  if [ -z "$field1" ]; then
    if [ "$HASH_ECHO" == 'true' ]; then
      read -r -p "Enter $msg: " field1 field2 || exit 1
      [[ -t 0 ]] && echo
    else
      read -r -p "Enter $msg: " -s field1 field2 || exit 1
      [[ -t 0 ]] && echo
    fi
  fi

  [[ -n "$field1" ]] || hash_die "Error: no input."

  set -- "${args[@]}"

  case "$cmd" in
    copy|move)
      local old_path new_path old_entry new_entry 

      [[ -n "$field2" ]] || hash_die "Error: missing destination path."

      old_path="$(echo "$field1" | hash_sum)" || exit 1
      new_path="$(echo "$field2" | hash_sum)" || exit 1

      old_entry="$(hash_index_get_entry "$old_path")" || \
        hash_die "Error: current password name not found in hash index."

      new_entry="$(hash_make_entry "$new_path")"

      cmd_copy_move "$@" \
        "$HASH_DIR/$(echo "$old_entry" | hash_get_salted_path)" \
        "$HASH_DIR/$(echo "$new_entry" | hash_get_salted_path)"

      [[ "$cmd" == "move" ]] && hash_index_delete "$old_path"
      hash_index_update "$new_entry"
      ;;
    generate)
      local path len entry

      path="$(echo "$field1" | hash_sum)" || exit 1
      len="${field2:-}"

      if ! entry="$(hash_index_get_entry "$path")"; then
        entry="$(hash_make_entry "$path")"
      fi

      cmd_generate "$@" \
        "$HASH_DIR/$(echo "$entry" | hash_get_salted_path)" "$len"
      hash_index_update "$entry"
      ;;
  esac
}

hash_cmd_single_field() {
  local cmd args path pass entry
  hash_index_check || hash_die "Error: no pass-hash index."
  cmd="$1" # delete|edit|find|insert|show
  shift
  args=( "$@" )
  # find if path is an argument
  while [ "$#" -gt 0 ]; do
    case "$cmd" in
      delete) # [--recursive,-r] [--force,-f] pass-name
        case "$1" in
          -*) shift ;;
          *) path="$1"; unset "args[-$#]" ; break ;;
        esac
        ;;
      edit) # pass-name
          path="$1"; unset "args[-$#]"; break
          ;;
      edit)
        path="$1"; unset "args[-$#]"; break
        ;;
      insert) # [--echo,-e | --multiline,-m] [--force,-f] pass-name 
        case "$1" in
          -*) shift ;;
          *) path="$1"; unset "args[-$#]" ; break ;;
        esac
        ;;
      show) # [--clip[=line-number],-c[line-number]] pass-name
        case "$1" in
          -c|--clip) shift 2 ;;
          -c*|--clip=*) shift 1 ;;
          *) path="$1"; unset "args[-$#]" ; break ;;
        esac
        ;;
    esac
  done

  if [ -z "$path" ]; then
    if [ "$HASH_ECHO" == 'true' ]; then
      read -r -p "Enter password name: " path || exit 1
    else
      read -r -p "Enter password name: " -s path || exit 1
      [[ -t 0 ]] && echo
    fi
  fi

  # Capture any other lines of standard in
  read -t 0 && pass="$(cat)"

  if [ -n "$path" ]; then
    path="$(echo "$path" | hash_sum)" || exit 1
  elif [ "$cmd" != "show" ]; then
    hash_die "Error: no password name given."
  fi

  set -- "${args[@]}"
  case "$cmd" in
    delete)
      entry="$(hash_index_get_entry "$path")" || \
        hash_die "Error: password name not found in index."

      cmd_delete "$@" "$HASH_DIR/$(echo "$entry" | hash_get_salted_path)"
      hash_index_delete "$path"
      ;;

    edit)
      if ! entry="$(hash_index_get_entry "$path")"; then
        entry="$(hash_make_entry "$path")"
      fi
      cmd_edit "$@" "$HASH_DIR/$(echo "$entry" | hash_get_salted_path)"
      hash_index_update "$entry"
      ;;

    find)
      if ! entry="$(hash_index_get_entry "$*")"; then
        hash_die "Error: password name not found in index."
      fi
      cmd_find "$HASH_DIR/$(echo "$entry" | hash_get_salted_path)"
      ;;

    insert)
      if ! entry="$(hash_index_get_entry "$path")"; then
        entry="$(hash_make_entry "$path")"
      fi
      if [ -n "$pass" ]; then
        cmd_insert "$@" \
          "$HASH_DIR/$(echo "$entry" | hash_get_salted_path)" <<<"${pass:-}"
      else
        cmd_insert "$@" \
          "$HASH_DIR/$(echo "$entry" | hash_get_salted_path)"
      fi
      hash_index_update "$entry"
      ;;
      
    show)
      if [ -n "$path" ]; then
        entry="$(hash_index_get_entry "$path")" || \
          hash_die "Error: password name not found."

        cmd_show "$@" "$HASH_DIR/$(echo "$entry" | hash_get_salted_path)"
      else
        cmd_show "$@" "$HASH_DIR"
      fi
      ;;
  esac
}

hash_cmd_find() {
  local cmd
  cmd="$1" # find|grep
  shift
  export PREFIX="$PREFIX/$HASH_DIR"
  case "$cmd" in
    find)
      #echo "[pass-hash] Info: pass-hash store is hashed." >&2
      cmd_find "$@"
      ;;
    grep)
      cmd_grep "$@"
      ;;
  esac
}

hash_cmd_init() {
  local args path index_file
  args=( "$@" )
  while [ "$#" -gt 0 ]; do
    case "$1" in # [--path=subfolder,-p subfolder] gpg-id
      -p|--path)
        path="2"; unset "args[-$#]"; shift; unset "args[-$#]"; shift ;;
      -p*)
        path="${1#"-p"}"; unset "args[-$#]"; shift ;;
      --path=*)
        path="${1#"--path="}"; unset "args[-$#]"; shift ;;
      *) break ;;
    esac
  done

  HASH_DIR="${path:-"$HASH_DIR"}"
  cmd_init -p "$HASH_DIR" "$@"

  index_file="${HASH_DIR}/$(basename -- "${HASH_INDEX_FILE}")"
  cmd_insert -f -e "$index_file" <<< "$(cat /dev/null)"
}

hash_cmd_usage() {
  cat <<-_EOF
$HASH_PROGRAM $HASH_VERSION
Password Store Extension (https://passwordstore.org)

Usage:
  $PROGRAM hash [OPTIONS] COMMAND

Options:
  [-a|--algorithm 'name:command'] Set the algorithm used in hashing password  
                                  names and salts. Argument is a quoted string
                                  with the name of the algorithm and the
                                  command used to use it separated by a ':'.
                                  This script assumes the algorithm will be
                                  a SHA hash. If the command is ommitted,
                                  a suitable command will attempt to be found.
                                  This overrides the environment variable,
                                  PASSWORD_STORE_HASH_ALGORITHM.
                                  See ENVIRONMENT VARIALBLES for more info.

  [-e|--echo]                     Turn on local echo for entry of password
                                  names. Only applies to the password name 
                                  functionality of pass-hash. To also enable
                                  echo on pass (e.g., 'pass hash insert'), 
                                  this flag will need to be passed again.

  [-h|--help]                     This message.


  [-p|--path dir]                 Set the subdirectory path of the pass-hash
                                  store. Overrides PASSWORD_STORE_HASH_DIR.
                                  

Synposis:
  In most cases, pass-hash acts as a shim for standard pass commands.
  Simply precede 'hash' to any commands seen in 'pass help.'

  pass-hash extends standard pass in four ways:
    1)  Password names are accepted via standard in, instead of as arguments.
    2)  Password names are "hashed" with a randomly generated salt using an
        external program (default: SHA512) and kept with the hashed salt and
        the algorithm used to hash each in an encrypyted index.
    3)  A secondary subdirectory is used to store the hashed password names.
    4)  Every other function such as encrypting and decrypting the files, git
        actions, etc., is handled by pass directly.

  Unique to pass-hash is the password name, used as a path in standard pass,
  can be passed via standard in (STDIN). In cases where pass expects input
  on standard in (e.g., pass insert), separate the input by a new line. In
  the case of 'pass hash insert,' the first line of standard input would be
  the password name, the second line of standard input would be the password.

  Other Exceptions:
    - The hash index keeps a hashed version of your password name, a
      randomly (/dev/urandom) generated salt, and the algorithm each was
      hashed with. Meaning: your plaintext password name is not kept, which
      does break some functionality from standard pass. Any function that
      requires pass knowing the plaintext of the name will not work as expected
      if the full password name is not provided, including 'pass hash show' and
      'pass hash find'.

    - Unlike 'pass', you can only copy, move, and delete a hashed file by it's
      complete password name, as pass-hash doesn't create a full path of 
      separate directories for the password name. They are single hashed files
      stored in a separate subdirectory set by PASSWORD_STORE_HASH_DIR.

    - 'pass hash init' is a separate command from 'pass init', it's only job
      is to create and encrypt the hash index.

Environment Variables:

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
    Default: .pass_hash
    Sub-directory for the hashed password store.

  PASSWORD_STORE_HASH_ECHO
    Default: false
    Boolean to echo back user input of password names. Note: this only applies
    to the hash extension. For standard pass commands, this will need to be set
    again.

_EOF
}

hash_args=( "$@" )
# Parse pass-hash specific flags
while [ "$#" -gt 0 ]; do
  case "$1" in
    -e|--echo)
      HASH_ECHO='true'
      unset "hash_args[-$#]"; shift
      ;;
    -a|--algorithm)
      HASH_ALGORITHM="${2:-}"
      unset "hash_args[-$#]"; shift
      unset "hash_args[-$#]"; shift
      ;;
    -a*)
      HASH_ALGORITHM="${1#"-a"}"
      unset "hash_args[-$#]"; shift
      ;;
    --algorithm=*)
      HASH_ALGORITHM="${1#"--algorithm="}"
      unset "hash_args[-$#]"; shift
      ;;
    -p|--path)
      HASH_DIR="${2:-}"
      unset "hash_args[-$#]"; shift
      unset "hash_args[-$#]"; shift
      ;;
    -p*)
      HASH_DIR="${1#"-p"}"
      unset "hash_args[-$#]"; shift
      ;;
    --path=*)
      HASH_DIR="${1#"--path="}"
      unset "hash_args[-$#]"; shift
      ;;
    *)
      break
      ;;
  esac
done

HASH_INDEX_FILE="${PREFIX}/${HASH_DIR}/.hash-index"

set -- "${hash_args[@]}"
case "$1" in
  copy|cp) shift;           hash_cmd_double_field "copy" "$@" ;;
  delete|rm|remove) shift;  hash_cmd_single_field "delete" "$@" ;;
  edit) shift;              hash_cmd_single_field "edit" "$@" ;;
  find|search) shift;       hash_cmd_single_field "find" "$@" ;;
  generate) shift;          hash_cmd_double_field "generate" "$@" ;;
  grep) shift;              hash_cmd_single_field "grep" "$@" ;;
  help|--help) shift;       hash_cmd_usage ;;
  init) shift;              hash_cmd_init "$@" ;;
  insert|add) shift;        hash_cmd_single_field "insert" "$@" ;;
  rename|mv) shift;         hash_cmd_double_field "move" "$@" ;;
  show|ls|list) shift;      hash_cmd_single_field "show" "$@" ;;
  *)                        hash_cmd_usage ;;
esac

exit 0
