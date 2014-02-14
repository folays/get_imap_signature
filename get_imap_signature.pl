#!/usr/bin/perl -w
#
# Copyright (c) 2011 2012 2013
# Eric Gouyer <folays@folays.net>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

use strict;
no strict 'refs';
use warnings FATAL => qw(uninitialized);

use Getopt::Long qw(:config no_auto_abbrev require_order);
use IO::Socket;
use IO::Socket::INET;
use IO::Select;
use Time::HiRes qw(gettimeofday);
use POSIX qw(strftime);
use Digest::MD5 qw(md5_hex);
use JSON;
use Data::Dumper;

my $quiet;
my %long_opts = (sockets => 1, max => 1, remote => "imap", port => 143, mode => 'signature');
if (open FILE, "<", "$ENV{HOME}/.get_imap_signature.conf")
{
    my $data = do { local $/ = undef; <FILE> };
    my $json = decode_json($data) or die;
    @long_opts{keys %$json} = values %$json;
    close FILE;
}
GetOptions("quiet", => \$quiet,
           "sockets=i" => \$long_opts{sockets},
	   "max=i" => \$long_opts{max},
	   "remote=s" => \$long_opts{remote},
	   "port=i" => \$long_opts{port},
	   "login=s" => \$long_opts{login},
	   "pw=s" => \$long_opts{pw},
	   "mode=s", \$long_opts{mode},
	   "skip-flag", \$long_opts{skip_flag},
	   "body" => \$long_opts{fetch_body},
    ) or &logfail("bad options");

die "no login or pw" unless $long_opts{login} && $long_opts{pw};

die if $long_opts{sockets} > $long_opts{max};

my $sel_r = IO::Select->new();
my $sel_w = IO::Select->new();

my %sockets;

for (1 .. $long_opts{sockets})
{
    &imap_start_thread;
}
my $now_string = strftime "%Y %m %d %H:%M:%S", localtime;
print "all threads started $now_string.\n";

#sleep 1;

my $total = 0;
my $last_time = &get_time;
my $imap_per_second_limit = 150;

$SIG{INT} = sub
{
    print "Total nb imaps: $total\n";
    exit 0;
};

while (1)
{
    last if $total == $long_opts{max};

#    print "SELECT on ".$sel_r->count()."\n";
    my ($r, $w) = IO::Select->select($sel_r, $sel_w, undef);
    foreach (@$r)
    {
#	next unless $sockets{$_};
	&do_read($_);
    }
    foreach (@$w)
    {
#	print "WRITE\n";
#	next unless $sockets{$_};
	&do_write($_);
    }
}

sub imap_start_thread
{
    my $s = IO::Socket::INET->new(PeerAddr => $long_opts{remote}, PeerPort => $long_opts{port}) or die;
    $sockets{$s} = {"s" => $s, state => "ready"};
#    print "add socket s/".$s." hash/".$sockets{$s}."\n";
    $sel_r->add($s);
#    print "count ".$sel_r->count()."\n";
}

sub get_login($)
{
    my ($d) = @_;

    (my $r = $long_opts{login}) =~ s/X(?=X*@)/int(rand(10))/oge;
    return $r;
}

sub get_time
{
    my ($seconds, $microseconds) = gettimeofday;

    return $seconds * 1000 + $microseconds / 1000;
}

sub do_read
{
    my ($s) = @_;

    my $buf;
    my $ret = sysread $s, $buf, 1024;
    if (not defined $ret)
    {
	die "not defined\n";
    }
    elsif (!$ret)
    {
#	die "read 0 $? $!";
	$sel_r->remove($s);
	$sel_w->remove($s);
	delete $sockets{$s};
	++$total;
	&imap_start_thread if scalar(keys %sockets) < ($long_opts{max} - $total);
    }
    &filter_read($sockets{$s}, \$buf);
}

sub filter_read($$)
{
    my ($d, $buf) = @_;

    my $buffer = \$d->{buffer};
    $$buffer = [undef] unless ref $$buffer;
    while ($$buf =~ m/(.*)(\n)?/go)
    {
	my $linebuf = \$$buffer->[$#{$$buffer}];
	$$linebuf .= $1;
#	print "--> $1\n" if defined $2;
	do { $$linebuf =~ s/\r$//o; push @{$$buffer}, undef } if defined $2;
    }
#    pop @{$$buffer} if !(length $$buf || length $$buffer->[$#{$$buffer}]);
#    while (scalar @{$$buffer} && length $$buffer->[0])
    while (scalar @{$$buffer} >= 2)
    {
	my $line = shift @{$$buffer};
	&imap_read($d, $line);
#	print "new buffer number of lines is ".scalar ( @{$$buffer} )."\n";
    }
}

sub do_write($)
{
    my ($s) = @_;

#    print "do_write to $d\n";
#    print "len : ".($d->{outbuf} || "NULL")."\n";
    my $buffer = \$sockets{$s}{outbuf};
#    print "syswrite ".($d || "NULL")." ".($$buffer || "NULL")."\n";
    my $ret = syswrite $sockets{$s}{s}, $$buffer;
    substr $$buffer, 0, $ret, "";
    $sel_w->remove($s) unless length $$buffer;
}

sub imap_write
{
    my ($d, $data) = @_;

    $data = ". ".$data;
    print ">>> \e[31m$data\e[0m\n" unless $quiet;
    $d->{outbuf} .= $data."\r\n";
#    print "add select hash/".$d." s/".$d->{s}." state/".$d->{state}."\n";
    $sel_w->add($d->{s});
}

sub imap_read
{
    my ($d, $line) = @_;

    print "<<< \e[32m$line\e[0m\n" unless $quiet;
#    return unless $line =~ m/^(\d+) /;
    die unless $line =~ m/^([.*]) (.*)$/;
    my $code = $1;
    my $func = "imap_read_".$d->{state};
    my $ret = &{$func}($d, $code eq ".", $2);
    if (!$ret)
    {
	die "DIE $func: $line\n";
    }
}

sub imap_read_ready($$$)
{
    my ($d, $code, $line) = @_;

    if (!$code && $line =~ m/^OK /o)
    {
	$d->{global_hash} = 0;
	$d->{login} = &get_login($d);
	&imap_write($d, "login ".$d->{login}." \"".$long_opts{pw}."\"");
	$d->{state} = "login";
    }
    else
    {
	die "bad greetings";
    }
}

sub imap_read_login($$$)
{
    my ($d, $code, $line) = @_;

    if ($code && $line =~ m/^OK /o)
    {
	&imap_write($d, "namespace");
	$d->{state} = "namespace";
    }
}

sub imap_read_namespace($$$)
{
    my ($d, $code, $line) = @_;

    if ($code && $line =~ m/^OK /o)
    {
	&imap_write($d, 'lsub "" "*"');
	$d->{state} = "lsub";
	$d->{folders_list} = [];
    }
    else
    {
	1;
    }
}

sub imap_read_lsub($$$)
{
    my ($d, $code, $line) = @_;

    if ($code && $line =~ m/^OK /o)
    {
	$d->{folder_lsub_n} = 0;
	$d->{folders_lsub} ||= [];
	@{$d->{folders_lsub}} = sort { $a->{name} cmp $b->{name} } @{$d->{folders_lsub}};
	my $hash_folders = unpack("L", substr(md5_hex(join(' ', map { $_->{name} } @{$d->{folders_lsub}})), 0, 4));
#	print "HASH of lsub ".$hash_folders."\n";
#	$d->{global_hash} = ($d->{global_hash} * 31 + $hash_folders) % 2**30;
	&imap_write($d, 'list "" "*"');
	$d->{state} = "list";
    }
    elsif (!$code && $line =~ m/^(?:LSUB|LIST) \((.*)\) "([\/.])" (?|([^"\s]+)|"([^"]+)")?$/o)
    {
	push @{$d->{folders_lsub}}, {name => $3, separator => $2, flags => $1};
	1;
    }
}

sub imap_read_list($$$)
{
    my ($d, $code, $line) = @_;

    if ($code && $line =~ m/^OK /o)
    {
	$d->{folder_list_n} = 0;
	@{$d->{folders_list}} = sort { $a->{name} cmp $b->{name} } values %{{map { $_->{name} => $_ } @{$d->{folders_list}}}};
	print "===> ".join(' ', map { $_->{name} } @{$d->{folders_list}})."\n";
	my $hash_folders = unpack("L", substr(md5_hex(join(' ', map { (my $name = $_->{name}) =~ s/\./\//go; $name; }@{$d->{folders_list}})), 0, 4));
#	print "HASH of list ".join(' ', map { $_->{name} }@{$d->{folders_list}})."\n";
	print "HASH of list ".$hash_folders."\n";
	$d->{global_hash} = ($d->{global_hash} * 31 + $hash_folders) % 2**30;
	&imap_read_uid($d, "?", "OK ")
    }
    elsif (!$code && $line =~ m/^LIST \((.*)\) "([\/.])" (?|([^"\s]+)|"([^"]+)")?$/o)
    {
	push @{$d->{folders_list}}, {name => $3, separator => $2, flags => $1};
	1;
    }
}

sub imap_read_examine($$$)
{
    my ($d, $code, $line) = @_;

    if ($code && $line =~ m/^OK /o)
    {
	my $fetch_items = join(" ", qw(FLAGS),
			 $long_opts{fetch_body} ? "BODY" : (),
	    );
	&imap_write($d, "uid fetch 1:* ($fetch_items)");
	$d->{cur_hash} = 0;
	die unless $d->{uid_validity} && $d->{uid_next};
	$d->{state} = "uid";
    }
    elsif (!$code)
    {
	$d->{uid_validity} = $1 if ($line =~ m/OK \[UIDVALIDITY (\d+)\]/);
	$d->{uid_next} = $1 if ($line =~ m/OK \[UIDNEXT (\d+)\]/);
	1;
    }
}

sub imap_read_uid($$$)
{
    my ($d, $code, $line) = @_;

    if ($code && $line =~ m/^OK /o)
    {
	if ($code ne "?")
	{
#	    my $folder_hash = ($d->{cur_hash} * 31 + $d->{uid_validity} * 7 + $d->{uid_next} * 3) % 2**30;
	    my $folder_hash = ($d->{cur_hash} * 31 + $d->{uid_validity} * 7) % 2**30;
	    print "HASHes of folder ".$d->{cur_folder}." : ".$d->{uid_validity}." ".$d->{uid_next}." ".$d->{cur_hash}." => ".$folder_hash." [".$d->{global_hash}."]\n";
	    $d->{global_hash} = ($d->{global_hash} * 31 + $folder_hash) % 2**30;
	}
	while ($d->{folder_list_n} < scalar @{$d->{folders_list}})
	{
	    my $folder = $d->{folders_list}->[$d->{folder_list_n}++];

	    next if $folder->{flags} =~ m/\\NoSelect/o;

	    $d->{cur_folder} = $folder->{name};
	    &imap_write($d, 'examine "'.$d->{cur_folder}.'"');
	    $d->{uid_validity} = undef;
	    $d->{uid_next} = undef;
	    $d->{list_uid} = undef;
	    $d->{state} = "examine";
	    return 1;
	}
	&imap_write($d, "logout");
	$d->{state} = "end";
    }
    else
    {
	if ($line =~ m/^(\d+) FETCH \(UID (\d+) FLAGS \((.*)\)\)$/)
	{
	    print "WARNING : Duplicate UID $2 in folder ".$d->{cur_folder}."\n" if exists $d->{list_uid}->{$2};
	    $d->{list_uid}->{$2} = undef;
	    $d->{cur_hash} = ($d->{cur_hash} * 31 + $2) % 2**30;
	    my @flags = sort $3 =~ m/(?:^|\G)\\(\S+)\s?/ogm;
	    my $hash_flags = unpack("L", substr(md5_hex(join(' ', @flags)), 0, 4));
	    $d->{cur_hash} = ($d->{cur_hash} * 31 + ($long_opts{skip_flag} ? 0 : $hash_flags)) % 2**30;
	    1;
	}
    }
}

sub imap_read_end
{
    my ($d, $code, $line) = @_;

    if ($code && $line =~ m/^OK /o)
    {
#	print "IMAP SENT ".$d->{recipient}."\n";
	if (++$total % $imap_per_second_limit == 0)
	{
	    my $ms = $imap_per_second_limit * 1000 / (&get_time - $last_time);
	    while ($ms >= $imap_per_second_limit)
	    {
		select undef, undef, undef, 0.050;
		$ms = $imap_per_second_limit * 1000 / (&get_time - $last_time);
#		printf "new imaps/second : %.02f\n", $ms;
	    }
	    printf "imaps/second : %.02f\n", $ms;
	    $last_time = &get_time;
	}
	if ($total == $long_opts{max})
	{
	    print "maximum number of imaps have been sent (".$long_opts{max}.")\n";
	    print "GLOBAL HASH : ".$d->{global_hash}."\n";
	    exit 0;
	}
#	die if $total == 1000;
	# it won't work from there because `logout' close the socket anyway...
	#&imap_read_login($d, $code, $line);
	return 1;
    }
    elsif (!$code && $line =~ m/^BYE /o)
    {
	1;
    }
}
