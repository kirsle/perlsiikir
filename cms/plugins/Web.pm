package Siikir::Plugin::Web 2011.0930;

use 5.14.0;
use strict;
use warnings;

use base "Siikir::Plugin";

sub init {
	my $self = shift;

	$self->debug("Web plugin loaded!");

	# This is just a dumb wrapper that requires other plugins.
	$self->requires(qw(
		JsonDB
		CGI
		Session
		User
		Page
		Mobile
	));
}

1;
