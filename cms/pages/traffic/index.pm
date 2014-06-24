package Siikir::Controller::traffic::index;

use strict;
use Siikir::Util;
use URI::Escape;

sub process {
	my ($self, $vars, $url) = @_;

	# We need the Traffic plugin.
	$self->Master->loadPlugin("Traffic");

	my $action = scalar @{$url} ? $url->[0] : "index";
	$vars->{action} = $action;

	# Actions.
	if ($action eq "hits") {
		# Get the hit history.
		$vars->{history} = $self->Master->Traffic->getDetails();
	}
	elsif ($action eq "referers") {
		# Get all the referrers.
		$vars->{referers} = $self->Master->Traffic->getReferers();

		# Make google searches look better.
		my %google = ();
		$vars->{google} = [];
		for (my $i = 0; $i < scalar @{$vars->{referers}->{referers}}; $i++) {
			my $link = $vars->{referers}->{referers}->[$i];
			$link->[0] = Siikir::Util::stripHTML($link->[0]);

			if ($link->[0] =~ /google/ && $link->[0] =~ /[^\w]q=([^&]+)/) {
				my $query = $1;
				$query =~ s/\+/%20/g;
				$query = uri_unescape($query);
				$google{$query} += $link->[1];
				$link->[0] = "wtf";
				splice(@{$vars->{referers}->{referers}}, $i, 1, undef);
				next;
			}

			# Clean up useless google links.
			if ($link->[0] =~ /google/ && $link->[0] =~ /\/(?:imgres|url|search|translate\w+)\?/) {
				splice(@{$vars->{referers}->{referers}}, $i, 1, undef);
				next;
			}
		}
		$vars->{google} = [ map {
			[ $_ => $google{$_} ]
		} sort { $google{$b} <=> $google{$a} || $a <=> $b } keys %google ];

		use Data::Dumper;
		#die Dumper($vars->{referers}) . "\n" . Dumper($vars->{google});
	}

	return $vars;
}

1;
