get_imap_signature
==================

test and hash the characteristics of an email account
(and quickly test that a mail account is working)

usage : ./get_imap_signature.pl -remote=imap.domain.tld -login=postmaster@domain.tld -pw=wtfareyouusingaweakpassword

This script will do some plain TCP (no IMAP modules) to fetch all IMAP directories, mail flags and so on, so that it
will finally yield a "GLOBAL HASH", which can be used as a signature to check that an account was correctly migrated.
