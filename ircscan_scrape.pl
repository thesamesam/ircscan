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
        ircd   text         NOT_NULL,
        vers   text         NOT_NULL
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
    if($_ =~ /N=/) {
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
  } elsif($_ =~ /S=/) {
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
    my $id           = "";
    my $ircd         = "";
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
        print "=> already got $server_host, skipping\r\n";
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
        $socket->read($data, 1024) if($tls);
        $socket->recv($data, 1024) if(!$tls);

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
                $id  = (split("running version", $good_bits))[1];
                # strip out anything after the first space
                $id =~ s/^\s+//;

                # let's grab the actual ircd
                if($id =~ /-/) {
                    my @split_dash = split("-", $id);
                    my $dash_count = @split_dash;

                    # If there are multiple dashes, e.g. ircd-seven-X.X.X, take this into account.
                    # (The if has > 2 instead of > 1 because a string with one dash produces two chunks)
                    if($dash_count > 2) {
                        my $found_integer = 0;
                        for(my $k = 0; $k < $dash_count; $k++) {
                            # See below comments. Start counting everything as a version once we see the first integer.
                            $found_integer = 1 if($split_dash[$k] =~ /\d/);

                            if($found_integer && $ircd ne '') {
                                # A version string may span multiple dashes.
                                # Consider 'charybdis-4-rc3'. The version is '4-rc3'.
                                # The solution is to continue the below logic UNTIL we find an integer, then count everything as the version.
                                $version .= $split_dash[$k];
                                # Only append if not last chunk (see below)
                                $version .= "-" if($k < ($dash_count - 1));
                            } else {
                                # Consider 'ircd-seven-1.1.4' (Freenode)
                                # If we are in the last part of the split('-'), it is actually the version (1.1.4)
                                # split('-') => ['ircd', 'seven', "1.1.4"]
                                if($k == ($dash_count - 1)) {
                                    $version = $split_dash[$k];
                                } else {
                                    # Not the last part? Then it's still, by definition, a fragment of a string with -s.
                                    # With our example, it could be 'ircd' or 'seven'.
                                    # So append it to the previous chunk.
                                    $ircd .= $split_dash[$k];
                                    # Only append an additional '-' if we are not the last chunk.
                                    # This prevents strings like 'ircd-seven-' being formed.
                                    $ircd .= "-" if($k < ($dash_count - 2));
                                }
                            }
                        }

                        # Strip a trailing - just in case
                        $ircd =~ s/-$//;
                    } else {
                        $ircd    = $split_dash[0];
                        $version = $split_dash[1];

                        # Special patch version at the end?
                        # Consider 'UnrealIRCd3.2.10.3-gs' (GeekShed)
                        # We would call the ircd 'UnrealIRCd-gs', with a version of '3.2.10.3'
                        # TODO: We could count everything up to the character before the first '.'
                        # TODO: Then would only count numbers as a version.. and append the first and last parts.
                        # TODO: Quite messy. Need to see if it's satisfactory to leave this as-is.
                        # TODO: This still isn't covered by the other code to deal with if we've seen an integer yet
                    }

                    # Parentheses? Need to consider these too. They need to be balanced.
                    # Consider 'plexus-4(hybrid-8.1.20)' (Rizon)
                    # The ircd will be 'plexus-4(hybrid' because this is up to the last '-#.
                    # Another problematic string was 'bahamut-1.8(06)' (EnterTheGame).
                    if($id =~ /\(/ || $id =~ /\)/) {
                        # Overall they're unbalanced. Need to find out where.
                        my $left_ircd_parens  = ($ircd =~ /\(/);
                        my $right_ircd_parens = ($ircd =~ /\(/);
                        if($left_ircd_parens != $right_ircd_parens) {
                            if($left_ircd_parens > $right_ircd_parens) {
                                $ircd .= "\)";
                            } else {
                                $ircd  =~ s/\)//;
                            }
                        }

                        my $left_version_parens  = ($version =~ /\(/);
                        my $right_version_parens = ($version =~ /\(/);
                        if($left_version_parens != $right_version_parens) {
                            if($left_version_parens > $right_version_parens) {
                                $version .= "\)";
                            } else {
                                $version  =~ s/\)//;
                            }
                        }
                    }

                } else {
                    # Not all IRCds like to use a dash.
                    # Consider 'Unreal3.2.10.4'
                    # A similar principle applies as with some of the dash parsing code.
                    my $found_integer = 0;
                    my $current_char  = '';
                    for(my $k = 0; $k < length $id; $k++) {
                        # Check all of the characters
                        # All characters are part of the ircd until we find an integer
                        # Once we've found an integer, we count it as part of the version.
                        $current_char  = substr($id, $k, 1);
                        $found_integer = 1 if($current_char =~ /\d/);

                        $ircd    .= $current_char if(!$found_integer);
                        $version .= $current_char if($found_integer);
                    }
                }

                print "=> got id:   $id\r\n";
                print "=> got ircd: $ircd\r\n";
                print "=> got version: $version\r\n";

                if($ircd eq '') {
                    print "=> couldn't parse version from $server_host, skipping\r\n";
                    print "=> if you're sure $server_host:$server_port is listening and you have already retried, please report this as a bug\r\n";
                    $count++;
                    next NETWORK_LOOP;
                }

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
    $query = $dbh->prepare("INSERT INTO servers VALUES(?, ?, ?, ?, ?, ?)");
    $query->execute($rowid, $server_host, $server_port, $tls, $ircd, $version);

    $count++;
}
