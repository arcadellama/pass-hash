# pass-hash
A [pass](https://www.passwordstore.org/) extension for obfuscating path stores.

The security model for standard pass is to encrypt the contents of a file, however this directory and file are kept in plain-text.
This extension amends this functionality to create a second store of entries whose paths (or 'keys') are salted and hashed.

In most cases, pass-hash acts as a shim for standard pass commands.
Simply precede 'hash' to any commands seen in 'pass help.' However, as the name of the path (or key) is meant to be obfuscated, it is not recommended to include the path as a command argument as you would normally in pass. Instead, the user will be prompted to type the path directly into a hash program (shasum, sha512sum, etc.). User can also pass the path in via STDIN.

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

ENVIRONMENT VARIABLES

  PASSWORD_STORE_HASH_ALGORITHM
    The SHA algorithm to use when hashing new files. Default: SHA512

  PASSWORD_STORE_HASH_DIR
    Sub-directory for the hashed password store. Default: .pass_hash
