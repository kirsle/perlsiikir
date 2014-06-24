package Siikir::Controller::emoticons;

use strict;
use Siikir::Util;

sub process {
	my ($self, $vars, $url) = @_;

	$self->Master->loadPlugin("Emoticons");
	my $theme = scalar @{$url} > 0 ? $url->[0] : "default";

	# Load the smiley theme.
	$vars->{http}    = $self->Master->Emoticons->http();
	$vars->{smileys} = $self->Master->Emoticons->loadTheme($theme);

	return $vars;
}

1;
