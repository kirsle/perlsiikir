package Siikir::Controller::account::logout;

use strict;

sub process {
	my ($self, $vars, $url) = @_;

	# Easy, log them out.
	$self->Master->User->forget();
	$vars->{account} = {};
	$vars->{login}   = 0;
	$vars->{uid}     = 0;

	# Send them back home.
	$self->Master->CGI->redirect("/");

	return $vars;
}

1;
