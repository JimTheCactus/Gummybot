#!/bin/perl
use strict;
use warnings;
use Storable;

my %memos;
my %greets;
my @reminders = ();
my %datastore;

%greets=();
%memos=();
my $filename = shift;
if (-e $filename) {
	%memos = %{retrieve($filename)};
}
$filename = shift;
if (-e $filename) {
	%greets = %{retrieve($filename)};
}
$datastore{greets}=\%greets;
$datastore{memos}=\%memos;
$datastore{reminders}=\@reminders;
$filename = shift;
store \%datastore, $filename;
