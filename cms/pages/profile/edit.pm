package Siikir::Controller::profile::edit;

use strict;
use Siikir::Util;

sub process {
	my ($self, $vars, $url) = @_;

	# We need the Profile plugin.
	$self->Master->loadPlugin("Profile");
	$vars->{fields} = $self->Master->Profile->fields();

	# Must be logged in.
	if (!$vars->{login}) {
		return $vars;
	}

	# Fetch our current profile.
	$vars->{values} = $self->Master->Profile->getProfile($vars->{uid});

	# Did they submit the form?
	my $action = scalar(@{$url}) ? $url->[0] : "index";
	if ($action eq "save") {
		# Attempting to save changes. Parse their params against the fields!
		my $data = Siikir::Util::paramFields($vars->{fields}, $vars->{param});
		$vars->{errors}   = $data->{errors};
		$vars->{warnings} = $data->{warnings};

		# Set all the profile params.
		my $success = $self->Master->Profile->setFields($vars->{uid}, $data->{fields});
		if ($@) {
			push (@{$vars->{errors}}, $@);
		}

		$vars->{success} = $success;
	}

	return $vars;
}

1;
