#!/usr/bin/perl -w

# Re-calculae everybody' locations from their zipcodes.

use lib "../src";
use strict;
use Siikir;

my $cms = Siikir->new(
	debug => $ENV{X_SIIKIR_DEBUG} || 0,
	root  => "..",
);
$cms->loadPlugin("Search");
$cms->Search->buildCache();

print "Rebuilt search cache.\n";
