#!/usr/bin/perl -w

use strict;
use warnings;
use JSON;

my $json = JSON->new->utf8->pretty();

my $output = {
	name   => "Tango",
	source => "http://digsbies.org/site/content/project/tango-emoticons-big-pack",
	map    => {},
};

open (my $emo, "<", "emoticons.txt");
while (my $line = <$emo>) {
	chomp $line;
	$line =~ s/[\x0D\x0A]+//g;
	$line =~ s/^\s+//g;
	$line =~ s/\s+$//g;
	next unless length $line;

	my ($img,@codes) = split(/\s+/, $line);
	$output->{map}->{$img} = [ @codes ];
}
close($emo);

open (my $out, ">", "emoticons.json");
print {$out} $json->encode($output);
close($out);
