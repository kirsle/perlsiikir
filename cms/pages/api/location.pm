package Siikir::Controller::api::location;

use strict;
use Siikir::Util;

sub process {
	my ($self, $vars, $url) = @_;

	# We need raw text output.
	$vars->{layout} = "text";

	# Only bother if they're logged in.
	if (!$vars->{login}) {
		$vars->{errors} = [ "User is not logged in. Try /api/auth first." ];
		return $vars;
	}

	$self->Master->loadPlugin("Profile");
	$self->Master->loadPlugin("Search");
	$vars->{profile} = $self->Master->Profile->getProfile($vars->{uid});

	# Update their location?
	my $lat = $vars->{param}->{latitude};
	my $lon = $vars->{param}->{longitude};
	my $acc = $vars->{param}->{accuracy};
	if ($lat && $lon) {
		if ($lat =~ /[^0-9\.\-\+]/ || $lon =~ /[^0-9\.\-\+]/) {
			$vars->{errors} = [ "Invalid format for latitude or longitude." ];
			return $vars;
		}

		# Set their GPS-location.
		$self->Master->Profile->setFields($vars->{uid}, {
			"gps-latitude"  => $lat,
			"gps-longitude" => $lon,
			"gps-accuracy"  => $acc,
		});

		# Rebuild search cache.
		$self->Master->Search->buildCache();
	}
	else {
		$vars->{errors} = [ "No coordinates given." ];
	}

	return $vars;
}

1;
