#!/usr/bin/perl
# author: sam <sam@cmpct.info>
# a script to scrape the hexchat default server list
# stores ircd/version of each in sqlite db
# todo: could be used to tell them if it's out of date
use strict;
use warnings;
use DBI;
use IO::Socket::INET;
use IO::Socket::SSL;

# general config
my $DBFILE   = "ircdump.sqlite";
my $HXFILE   = "/home/sam/.config/hexchat/servlist.conf";
# irc config
my $USERNAME = "scrape";
my $NICKNAME = "scrape" . int(rand(1000));
my $REALNAME = "scrape";
my $QUIT     = "thanks";

sub setup_db {
  my $handle = shift;
  my $qh;

  # Create network table
  $qh = $handle->prepare("
CREATE TABLE networks(
    name text          NOT NULL
);");
  $qh->execute();

  # Create servers table
  $qh = $handle->prepare("
CREATE TABLE servers(
    nid    int          NOT NULL,
    host   text         NOT NULL,
    port   text         NOT NULL,
    tls    boolean,
    ver    text         NOT_NULL
);");
  $qh->execute();
}

sub read_file {
  my $handle;
  my @lines = ();
  open($handle, "<", $HXFILE) or die "couldn't read file";
  while(my $line = <$handle>) {
    push @lines, $line;
  }
  return @lines;
}

my @data     = read_file();
my $servers  = {};
my $name;
my $server;
my $query;

my $db_exists = (-e $DBFILE);
my $dbh       = DBI->connect("dbi:SQLite:dbname=$DBFILE", "", "");
setup_db($dbh) if !$db_exists;

foreach(@data) {
  # Collect all of the network names and corresponding servers
  chomp;
  if($_ =~ /N/) {
    $name   = (split("="))[1];
    $servers->{$name} = ();
    # Tell the db about new server name
    $query = $dbh->prepare("SELECT name FROM networks WHERE name=?");
    $query->execute($name);
    if($query->rows == 0) {
      # Only add if not already present
      $query = $dbh->prepare("INSERT INTO networks VALUES(?)");
      $query->execute($name);
    }
  } elsif($_ =~ /S/) {
    $server = (split("="))[1];
    push @{$servers->{$name}}, $server;
  }
}

# got a list of servers for each network now
# just do one per network for now, lest they get upset
my $count = 1;
my $size  = scalar keys %$servers;

NETWORK_LOOP:foreach(keys(%$servers)) {
  my $network_name = $_;
  my $server_host  = $servers->{$network_name}[0];
  my $server_port  = (split("/", $server_host))[1] // "6667";
  my $tls          = ($server_port =~ qw/\+/) ? 1 : 0;
  my $version      = "";

  # Strip out anything after the / in $server_host (already parsed)
  $server_host =~ s/\/(.*)//;
  # Strip out the + for TLS if it lingered somehow
  $server_host =~ s/\+//;
  $server_port =~ s/\+//;

  # Get the network id for our servers table
  $query = $dbh->prepare("SELECT rowid FROM networks WHERE name=?");
  $query->execute($network_name);
  my $rowid = $query->fetch()->[0];

  # Skip if we already exist
  $query = $dbh->prepare("SELECT * FROM servers WHERE (host=? AND port=? AND tls=?)");
  $query->execute($server_host, $server_port, $tls);
  while($query->fetchrow_array) {
    # if there are any rows...
    print "already got $server_host, skipping\r\n";
    next NETWORK_LOOP;
  }

  print "[$count/$size] testing $server_host:$server_port [$network_name] [tls=$tls]\r\n";

  my $socket;
  if($tls) {
    $socket = IO::Socket::SSL->new(PeerAddr => $server_host, PeerPort => $server_port, Proto => 'tcp');
  } else {
    $socket = IO::Socket::INET->new(PeerAddr => $server_host, PeerPort => $server_port, Proto => 'tcp');
  }

  if(!$socket) {
    $count++;
    next;
  }

  $socket->syswrite("NICK $NICKNAME\r\n");
  $socket->syswrite("USER $USERNAME $USERNAME $USERNAME :$REALNAME\r\n");

  my $data;
  READ_LOOP:while(1) {
    $socket->recv($data, 1024);
    if($data eq '') {
        $count++;
        next NETWORK_LOOP;
    }

    my @split_lines = split("\r\n", $data);

    foreach(@split_lines) {
      my @split_space = split(' ');
      my @split_colon = split(':');

      if($split_space[1] eq '002') {
	# RPL_WELCOME
	my $good_bits = $split_colon[2];
	$version   = (split("running version", $good_bits))[1];
	$version =~ s/^\s+//;
	print "got version: $version\r\n";
	last READ_LOOP;
      } elsif($split_space[0] eq 'PING') {
	my $pong_cookie = $split_colon[1] // $split_space[1];
	# TRIVIA: some ircds (like inspircd) only support PONG cookie (sans colon)
	# TRIVIA: cmpctircd supported the colon-case first and supports both
	# TRIVIA: yet i am writing it without
	$pong_cookie = ":$pong_cookie" if($_ =~ /:/);
	$socket->write("PONG $pong_cookie\r\n");
      } elsif($_ =~ /ERROR/ or $_ =~ /CLOSING/) {
        $count++;
        next NETWORK_LOOP;
      }
    }
  }

  $socket->write("QUIT :$QUIT\r\n");
  $socket->close();

  # Add the server to the database now we've got the version
  $query = $dbh->prepare("INSERT INTO servers VALUES(?, ?, ?, ?, ?)");
  $query->execute($rowid, $server_host, $server_port, $tls, $version);

  $count++;
}
