#!/usr/bin/perl
# name: ircscan_html.pl
# author: sam <sam@cmpct.info>
# help: for use with ircscan_scrape.pl to generate a quick html table
# help: please run that first
use strict;
use warnings;
use HTML::Table;
use DBI;

# config
my $DBFILE = "ircdump.sqlite";
my $HTFILE = "ircds.html";

# open the db
die "$DBFILE does not exist; run scrape_hexchat.pl to generate it\r\n" if(!-e $DBFILE);
my $dbh = DBI->connect("dbi:SQLite:dbname=$DBFILE", "", "");

# fetch
my $html;
my $query;
$query = $dbh->prepare("SELECT host,ver FROM servers");
$query->execute();

my $table;
# first, a table of all the hosts and versions of ircds
$html = "List of known ircd hosts and the ircd versions as of scrape time:<br /><br /><br/>";
$table = new HTML::Table(-border => 5);
$table->setStyle("float:left; width:45%;");
$table->addCol("<b>Host</b>");
$table->addCol("<b>Version</b>");
while(my $row = $query->fetchrow_hashref()) {
  $table->addRow($row->{host}, $row->{ver});
}

$html .= $table->getTable();

# now a table of how common each one is
$table = new HTML::Table(-border => 5);
$table->setStyle("float:right; width:45%;");
$table->addCol("<b>Version</b>");
$table->addCol("<b>Count</b>");

$query = $dbh->prepare("SELECT ver, COUNT(*) FROM servers GROUP BY ver ORDER BY COUNT(*) DESC");
$query->execute();
while(my $row = $query->fetchrow_hashref()) {
  $table->addRow($row->{ver}, $row->{"COUNT(*)"});
}

$html .= $table->getTable();

# finally write it all out to file
open(my $fh, ">", $HTFILE) or die "can't open $HTFILE\r\n";
print $fh $html;
close($fh);
