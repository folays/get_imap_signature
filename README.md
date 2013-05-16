get_imap_signature
==================

test and hash the characteristics of an email account
(and quickly test that a mail account is working)

usage : ./get_imap_signature.pl -remote=imap.domain.tld -login=postmaster@domain.tld -pw=wtfareyouusingaweakpassword

This script will do some plain TCP (no IMAP modules) to fetch all IMAP directories, mail flags and so on, so that it
will finally yield a "GLOBAL HASH", which can be used as a signature to check that an account was correctly migrated.

```sh
folays@phenix:~$ ./get_imap_signature.pl
<<< * OK [CAPABILITY IMAP4rev1 LITERAL+ SASL-IR LOGIN-REFERRALS ID ENABLE IDLE STARTTLS AUTH=PLAIN AUTH=LOGIN] Dovecot ready.
>>> . login postmaster@domain.tld "winteriscoming"
<<< . OK [CAPABILITY IMAP4rev1 LITERAL+ SASL-IR LOGIN-REFERRALS ID ENABLE IDLE SORT SORT=DISPLAY THREAD=REFERENCES THREAD=REFS MULTIAPPEND UNSELECT CHILDREN NAMESPACE UIDPLUS LIST-EXTENDED I18NLEVEL=1 CONDSTORE QRESYNC ESEARCH ESORT SEARCHRES WITHIN CONTEXT=SEARCH LIST-STATUS QUOTA] Logged in
>>> . namespace
<<< * NAMESPACE (("" "/")) NIL NIL
<<< . OK Namespace completed.
>>> . lsub "" "*"
<<< * LSUB () "/" "INBOX"
<<< * LSUB () "/" "INBOX/Drafts"
<<< * LSUB () "/" "INBOX/Sent"
<<< * LSUB () "/" "INBOX/SPAM"
[...]
<<< * BYE Logging out
<<< . OK Logout completed.
maximum number of imaps have been sent (1)
GLOBAL HASH : 980759512
```

CONFIGURATION

You can put default configuration options in ~/.get_imap_signature.conf, in JSON format. Example:

```sh
folays@phenix:~$ cat .get_imap_signature.conf
{"login":"postmaster@domain.tld","pw":"winteriscoming"}
```

FEATURES

You can also make this script flooding if you want to test the performances of your server.

For example, fetch 10k signatures using 200 TCP sockets running over 1k mail accounts:
```sh
./get_imap_signature.pl -max=10000 -sockets=200 -login=accountXXX@domain.tld
```

all "X" characters before the "@" of the mail address will be replaced by a random number, so that you can for example
create 1k mail account on your server and let the script flood them.
