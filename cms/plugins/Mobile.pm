package Siikir::Plugin::Mobile 2011.0930;

use 5.14.0;
use strict;
use warnings;
use JSON;
use CGI::Carp qw(fatalsToBrowser);

use base "Siikir::Plugin";

=head1 NAME

Siikir::Plugin::Mobile - Support for a mobile website.

=cut

sub init {
	my $self = shift;

	$self->debug("Mobile plugin loaded!");

	# Options.
	$self->options (
		# Subdomain prefix to indicate mobile site view.
		subdomain => 'm.', # Include the dot

		# What layout file to use for the mobile site.
		layout    => "mobile", # mobile.html
	);

	# Hard-coded options.
	$self->{_agents} = [
		# HTTP User Agents to look for to indicate mobile site.
		"Android",
		"iPhone",
		"iPod",
		"iOS",
	];
}

=head1 METHODS

=head2 string layout ()

Return the name of the layout to use for the mobile site.

=cut

sub layout {
	my $self = shift;
	return $self->{layout};
}

=head2 bool isMobile ()

Check if the mobile site should be served.

=cut

sub isMobile {
	my $self = shift;

	# Check for the mobile subdomain.
	if ($ENV{SERVER_NAME} =~ /^\Q$self->{subdomain}\E/i || $ENV{SERVER_NAME} =~ /^www\.\Q$self->{subdomain}\E/i) {
		return 1;
	}

	return undef;
}

1;
