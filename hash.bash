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

#### General Functions ####
hash_die() {
	echo "[$HASH_PROGRAM] $*" >&2
	exit 1
}

hash_sum() {
  # This is the workhorse function of pass-hash, and any change to this needs
  # to be done with backwards-compatibility in mind.
  #
  # A default of SHA is assumed, but easily overriden in the future with
  # a new case entry.
  # 
  # Testing needs to be done across different POSIX systems to ensure
  # these SHA commands function correctly.
  #
  # This deviates a bit from how 'pass' handles such situations, like in tmpdir
  # in that it inefficiently processes some constants like which programs are
  # on the system each time it is called. However, because there can
  # conceivably be a mixed use of algorithms in situations with older index
  # entries, a re-check of commands would be neccessary anyways. So, a cleaner
  # and more readable code was opted for a slight increase in efficiency.
  
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
  esac
}

hash_secure_input() {
  # Early drafts of this script used stty -echo and read input directly
  # into the hash_sum which meant the plain text of the password name was never
  # kept in a variable. However, this broke compatibilty with 'pass' functions
  # like 'cmd_insert' which also expects passwords to come in on the standard
  # input. Author considers this acceptable as it is no more or less secure
  # than how 'pass' handles the passwords and files itself.

  local input input_again
  if [[ ! -t 0 ]] || [ "$HASH_ECHO" == 'true' ]; then
    read -r -p "Enter $1: " input || exit 1
  else
    read -r -s -p "Enter $1: " input || exit 1
    echo
    read -r -s -p "Re-enter $1: " input_again || exit 1
    echo

    [[ "$input" == "$input_again" ]] || \
      hash_die "Error: $1 doesn't match."
  fi
  echo "$input" | hash_sum 
}

hash_salt() {
  # Updating the first half of this pipe will not break future functionality.
  # Using 4096 lines of /dev/urandom is probably not necessary.
  head -4096 < /dev/urandom | hash_sum
}

hash_make_entry() {
  # TAB Delineated table
  # <hashed password name>  | <hashed salt> | <algorithm:command>
  #
  # Future versions should be able to add more data or meta data AFTER these
  # entries without breaking backwards compatibility.

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
hash_index_update() {
  # It is important that this command is only run after the 'pass' function
  # successfully makes updates to the system so that the index can stay in
  # sync.

  if hash_index_get_entry "$(echo "$1" | cut -f1)"; then
    hash_index_delete "$(echo "$1" | cut -f1)"
  fi

  { cmd_show "$HASH_INDEX_FILE"; echo "$1"; } | \
    cmd_insert -f -m "$HASH_INDEX_FILE" >/dev/null
}

hash_index_delete() {
  # This read loop a very inefficient way to replace a single line in a file 
  # and could be replaced with a simple 'grep -v "^$1	"'. However, by using the
  # built-in read there is (probably?) a minor reduction in exposing a secret
  # by not needing to pass the non-salted hash of the pass-name
  # to an external program as an argument.

  cmd_show "$HASH_INDEX_FILE" | \
    while read -r line; do
      case "$line" in
        "$1"\	*) continue ;;
        *) echo "$line"   ;;
      esac
    done | cmd_insert -f -m "$HASH_INDEX_FILE" >/dev/null
}

hash_index_get_entry() {
  # This could be replaced with a simple one-line to 'grep "^$1	"', however
  # this more inefficiently eliminates the need to call an external command
  # with the non-salted hash of the pass-name, which might reduce the
  # possiblity of exposing a secret.

  cmd_show "$HASH_INDEX_FILE" | \
    while read -r line; do
      case "$line" in "$1"\	*) echo "$line" ; return ;; esac
    done
  return 1
}

#### Pass Command Shim Functions ####
hash_cmd_copy_move() {
  local args cmd path old_path new_path old_entry new_entry

  [[ -f "$HASH_INDEX_FILE" ]] || hash_die "Error: pass-hash index not found."
  
  # copy|move [--force, -f] old-path new-path
  args=( "$@" )
  while [ "$#" -gt 0 ]; do
    case "$1" in
      copy|move) cmd="$1"; shift ;;
      -*) shift ;;
      *)
        if [ -n "$old_path" ]; then
          new_path="$(echo "$1" | hash_sum)"
        else
	  old_path="$(echo "$1" | hash_sum)"
        fi
	unset "${args[-$#]}"
        shift
        ;;
    esac
  done

  if [[ -z "$old_path" ]] && [[ -z "$new_path" ]]; then
    # It seems the expected behavior of requiring two entries via stdin is to  
    # keep it as one line.
    path="$(hash_secure_input "<old password name> <new password name>")"
    # shellcheck disable=SC2086
    set -- $path
    old_path="$1"
    new_path="$2"
  else
    cmd_copy_move "${args[@]}"
  fi 

  old_entry="$(hash_index_get_entry "$old_path")" || 
    hash_die "Error: current password name not found in hash index."
  new_entry="$(hash_make_entry "$new_path")"

  cmd_copy_move "${args[@]}" \
    "$HASH_DIR/$(echo "$old_entry" | hash_get_salted_path)" \
    "$HASH_DIR/$(echo "$new_entry" | hash_get_salted_path)"

  if [ "$cmd" == "move" ]; then
    hash_index_delete "$old_path" || \
      hash_die "Error: unable to delete entry from index."
  fi

  hash_index_update "$new_entry" || \
    hash_die "Error: unable to add new entry to index."
}

hash_cmd_delete() {
  local args path entry

  [[ -f "$HASH_INDEX_FILE" ]] || hash_die "Error: pass-hash index not found."
  
  # [ --recursive, -r ] [ --force, -f ] pass-name
  args=( "$@" )
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -*) shift ;;
      *)  path="$(echo "$1" | hash_sum)"; unset "args[-$#]" ;;
    esac
  done

  path="${path:-"$(hash_secure_input "password name")"}"

  entry="$(hash_index_get_entry "$path")" || \
    hash_die "Error: password name not found in index."

  cmd_delete "${args[$@]}" \
    "$HASH_DIR/$(echo "$entry" | hash_get_salted_path)"

  hash_index_delete "$path" || \
    hash_die "Error: unable to delete entry from index."
}

hash_cmd_edit() {
  local path entry

  [[ -f "$HASH_INDEX_FILE" ]] || hash_die "Error: pass-hash index not found."

  path="${1:-"$(hash_secure_input "password name")"}"

  if ! entry="$(hash_index_get_entry "$path")"; then
    entry="$(hash_make_entry "$path")"
    cmd_edit "$(echo "$entry" | hash_get_salted_path)"
    hash_index_update_entry "$entry" || \
      hash_die "Error: unable to add new entry to index."
  else
    cmd_edit "$(echo "$entry" | hash_get_salted_path)"
  fi
}

hash_cmd_find() {
  echo "'find' command does not work with pass-hash store." >&2
  cmd_find "$@"
}

hash_cmd_generate() {
  local args path len entry

  [[ -f "$HASH_INDEX_FILE" ]] || hash_die "Error: pass-hash index not found."
  
  # [ --no-symbols, -n ] [ --clip, -c ] [ --in-place,
  # -i | --force, -f ] pass-name [pass-length]
  args=( "$@" )
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -*) shift ;;
      *)
        if [ -n "$path" ]; then
          len="$1"
        else
          path="$(echo "$1" | hash_sum)"
        fi
        unset "args[-$#]"
        shift
        ;;
    esac
  done

  if [ -z "$path" ]; then
    path="$(hash_secure_input "<password name> <pass-length (optional)>")"
    # shellcheck disable=SC2086
    set -- $path
    path="$1"
    len="${2:-}"
  fi

  [[ -n "$len" ]] && export PASSWORD_STORE_GENERATED_LENGTH="$len"

  if ! entry="$(hash_index_get_entry "$path")"; then
    entry="$(hash_make_entry "$path")"
    cmd_generate "${args[@]}" "$(echo "$entry" | hash_get_salted_path)"
  else
    cmd_generate "${args[@]}" "$(echo "$entry" | hash_get_salted_path)"
  fi
  hash_index_update_entry "$entry" || \
      hash_die "Error: unable to add new entry to index."
}

hash_cmd_grep() {
  export PREFIX="$HASH_DIR"
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
    cmd_insert -f "$HASH_DIR/$(basename -- "$HASH_INDEX_FILE")"
}

hash_cmd_insert() {
  local args path entry

  [[ -f "$HASH_INDEX_FILE" ]] || hash_die "Error: run 'pass hash init' first."

  # [ --echo, -e | --multiline, -m ] [ --force, -f ] pass-name
  args=( "$@" )
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -*) shift ;;
      *)  path="$(echo "$1" | hash_sum)"; unset "args[-$#]"; break ;;
    esac
  done

  path="${path:-"$(hash_secure_input "password name")"}"

  if ! entry="$(hash_index_get_entry "$path")"; then
    entry="$(hash_make_entry "$path")"
  fi

  cmd_insert -m "${args[@]}" "$HASH_DIR/$(echo "$entry" | hash_get_salted_path)"

  hash_index_update_entry "$entry" || \
      hash_die "Error: unable to add new entry to index."
}

hash_cmd_show() {
  local args path entry

  [[ -f "$HASH_INDEX_FILE" ]] || hash_die "Error: pass-hash index not found."

  # [ --clip[=line-number], -c[line-number] ] [ --qrcode[=line-number],
  # -q[line-number] ] pass-name
  args=( "$@" )
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -*) shift ;;
      *)  path="$(echo "$1" | hash_sum)"; unset "args[-$#]"; break ;;
    esac
  done

  path="${path:-"$(hash_secure_input "password name")"}"

  [[ -n "$path" ]] || hash_die "Error: paths are hashed, nothing to show."

  entry="$(hash_index_get_entry "$path")" || \
    hash_die "Error: password name not found in index."

  cmd_show "${args[@]}" "$(echo "$entry" | hash_get_salted_path)"
}

#### Unique pass-hash command functions ####
# hash_cmd_import() {
# # Import passwords from the standard store into the hashed store with option
#   to move or copy.
# }

args=( "$@" )
# Parse pass-hash specific flags
while [ "$#" -gt 0 ]; do
  case "$1" in
    -e|--echo)
      HASH_ECHO='true'
      unset "args[-$#]"; shift
      ;;
    -a|--algorithm)
      HASH_ALGORITHM="${2:-}"
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

HASH_INDEX_FILE="${PREFIX}/${HASH_DIR}/.hash-index"

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
  *)                        hash_cmd_usage ;;
esac

exit 0
