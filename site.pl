#!/usr/bin/perl
use strict;
use warnings;
use Mojolicious::Lite;
use DBI;

get '/' => sub {
    my $context = shift;
    $context->render(
        template => 'list',
    );
};

app->start;

__DATA__
@@ list.html.ep
% my $dbh   = DBI->connect("dbi:SQLite:dbname=ircdump.sqlite", "", "");
% my $query = $dbh->prepare("SELECT COUNT(*) as count FROM servers");
% my $count;
% $query->execute();
% $count = ($query->fetchrow_array())[0];
Welcome to ircscan. A humble project to figure out what the most popular ircds are. There are <%= $count %> servers in the DB.<br /><br />

<table border="5" style="float:left; width:45%;">
    % my $query = $dbh->prepare("SELECT host,ver FROM servers");
    % $query->execute();
    <tr><td><b>Host</b></td><td><b>Version</b></td></tr>
        % while(my $row = $query->fetchrow_hashref()) {
            <tr>
            <td><%= $row->{host} =%></td>
            <td><%= $row->{ver}  =%></td>
            <tr/>
        % }
</table>

% $query = $dbh->prepare("SELECT ver, COUNT(*) AS count FROM servers GROUP BY ver ORDER BY COUNT(*) DESC");
% $query->execute();
<table border="5" style="float:right; width:45%;">
    <tr><td><b>Version</b></td><td><b>Count</b></td></tr>
        % while(my $row = $query->fetchrow_hashref()) {
            <tr>
            <td><%= $row->{ver} =%></td>
            <td><%= $row->{count}  =%></td>
            <tr/>
        % }
</table>
