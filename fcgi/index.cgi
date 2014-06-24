#!/opt/perl/bin/perl -T

BEGIN {
	$::BASEDIR = "./cms";
	unshift(@INC, "$::BASEDIR/src");
	chdir("..");
}

use strict;
use warnings;
use CGI;
use CGI::Carp "fatalsToBrowser";
use CGI::Fast;
use Siikir;

while (my $fast = CGI::Fast->new) {
	$::TIME_START = time();
	my $cms = Siikir->new(
		root  => "$::BASEDIR",
		debug => 0,
		cgi   => $fast,
	);
	$cms->loadPlugin("Web");
	$cms->Page->run();
}
