#!/opt/perl/bin/perl -T

BEGIN {
	$::BASEDIR = "./cms";
	$ENV{PATH} = "/opt/perl/bin:/usr/bin:/bin:/usr/sbin:/sbin";
	unshift(@INC, "$::BASEDIR/src");
}

use strict;
use warnings;
use CGI;
use CGI::Carp "fatalsToBrowser";
use CGI::Fast;
use Siikir;

#while (my $fast = CGI::Fast->new) {
	$::TIME_START = time();
	my $cms = Siikir->new(
		root  => "$::BASEDIR",
		debug => 0,
		cgi   => CGI->new(),
	);
	$cms->loadPlugin("Web");

	$cms->Page->run();
#}
