package Siikir::Controller::search;

use strict;
use Siikir::Util;

sub process {
	my ($self, $vars, $url) = @_;

	# Must be logged in.
	if (!$vars->{login}) {
		$self->Master->CGI->redirect("/account/login?return=/search");
		return $vars;
	}

	# We need a couple plugins.
	$self->Master->loadPlugin("Profile");
	$self->Master->loadPlugin("Photo");
	$self->Master->loadPlugin("Search");
	$vars->{photopub} = $self->Master->Photo->http();

	# What search are they doing?
	my $type = scalar @{$url} ? $url->[0] : "nearby";
	my $page = $vars->{param}->{page} || 1;
	$page = 1 if $page < 1;

	if ($type eq "nearby") {
		# Search all users and list those nearby.
		my $results = $self->Master->Search->search (
			type   => "nearby",
			seeker => $vars->{login} ? $vars->{uid} : 0,
			offset => $page - 1, #(($page - 1) * 16),
			count  => 16,
			zipcode => $vars->{param}->{zipcode} || '',
		);
		if ($results->{error}) {
			$vars->{errors} = [ $results->{error} ];
		}
		$vars->{results} = $results;
	}

	return $vars;
}

1;
