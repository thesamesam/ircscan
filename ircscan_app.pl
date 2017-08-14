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

get '/show' => sub {
    my $context = shift;
    my $ircd    = $context->param('ircd');
    my $version = $context->param('version');
    $context->render(
        ircd     => $ircd,
        version  => $version,
        template => 'version',
    );
};

app->start;

__DATA__
@@ layouts/main.html.ep
<!DOCTYPE html>
<html>
    <head>
        <title><%= title %></title>
    </head>
    <body>
        <%= content %>
    </body>
</html>


@@ list.html.ep
% title 'ircscan: home';
% layout 'main';
% my $dbh   = DBI->connect("dbi:SQLite:dbname=ircdump.sqlite", "", "");
% my $query = $dbh->prepare("SELECT COUNT(*) as count FROM servers");
% my $count;
% $query->execute();
% $count = ($query->fetchrow_array())[0];
Welcome to ircscan. A humble project to figure out what the most popular ircds are. There are <%= $count %> servers in the DB.<br /><br />

<table border="5" style="float:left; width:45%;">
    % my $query = $dbh->prepare("SELECT host,ircd,vers FROM servers");
    % $query->execute();
    <tr>
        <td><b>Host</b></td>
        <td><b>IRCd</b></td>
        <td><b>Version</b></td>
    </tr>
        % while(my $row = $query->fetchrow_hashref()) {
            <tr>
            <td><%= $row->{host} =%></td>
            <td><%= $row->{ircd} =%></td>
            <td><%= $row->{vers} =%></td>
            <tr/>
        % }
</table>

% $query = $dbh->prepare("SELECT ircd, vers, COUNT(*) AS count FROM servers GROUP BY ircd ORDER BY COUNT(*) DESC");
% $query->execute();
<table border="5" style="float:right; width:45%;">
    <tr>
        <td><b>IRCd</b></td>
        <td><b>Version</b></td>
        <td><b>Count</b></td>
    </tr>
        % while(my $row = $query->fetchrow_hashref()) {
            <tr>
            <td><a href="/show?ircd=<%= $row->{ircd} =%>"><%= $row->{ircd} =%></a></td>
            <td>
                % my @cache  = ();
                % my $vQuery = $dbh->prepare("SELECT vers FROM servers WHERE ircd=? ORDER BY vers ASC");
                % $vQuery->execute($row->{ircd});
                % while(my $vRow = $vQuery->fetchrow_hashref()) {
                    % next if($vRow->{vers} ~~ @cache);
                    % push @cache, $vRow->{vers};
                    <a href="/show?ircd=<%= $row->{ircd} =%>&version=<%= $vRow->{vers} =%>"><%= $vRow->{vers} =%><br />
                % }
            </td>
            <td><%= $row->{count}  =%></td>
            <tr/>
        % }
</table>

@@ version.html.ep
% title 'ircscan: version lookup';
% layout 'main';
% my $dbh   = DBI->connect("dbi:SQLite:dbname=ircdump.sqlite", "", "");
% my $query;
% if($version eq '') {
%   $query = $dbh->prepare("SELECT COUNT(*) as count FROM servers WHERE ircd=?");
%   $query->execute($ircd);
% } else {
%   $query = $dbh->prepare("SELECT COUNT(*) as count FROM servers WHERE ircd=? AND vers=?");
%   $query->execute($ircd, $version);
% }
% my $count;
% $count = ($query->fetchrow_array())[0];

You're interested in IRC servers running ircd: <%= $ircd %>, version: <%= $version ? $version : "any"%>. We found <%= $count %> of them. <br /><br />

% if($version eq '') {
%   $query = $dbh->prepare("SELECT host, port, tls FROM servers WHERE ircd=?");
%   $query->execute($ircd);
% } else {
%   $query = $dbh->prepare("SELECT host, port, tls FROM servers WHERE ircd=? AND vers=?");
%   $query->execute($ircd, $version);
% }
<table border="5" style="float:left; width:45%;">
    <tr>
        <td><b>Host</b></td>
        <td><b>Port</b></td>
        <td><b>TLS</b></td>
    </tr>
        % while(my $row = $query->fetchrow_hashref()) {
            <tr>
            <td><%= $row->{host} =%></td>
            <td><%= $row->{port} =%></td>
            <td><%= $row->{tls} ? "Yes" : "No" =%></td>
            <tr/>
        % }
</table>
