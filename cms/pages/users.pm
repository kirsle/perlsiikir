package Siikir::Controller::users;

# Alias to /profile/view/*

use strict;
use Siikir::Util;

sub process {
	my ($self, $vars, $url) = @_;

	# Delegate to profile/view
	no strict "refs";
	my $ns = $self->Master->Page->loadController("profile::view");
	$vars->{view} = "profile/view";
	$vars = $ns->($self, $vars, $url);

	return $vars;
}

1;
