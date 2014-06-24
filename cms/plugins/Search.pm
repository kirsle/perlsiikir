package Siikir::Plugin::Search 2011.1001;

use 5.14.0;
use strict;
use warnings;

use base "Siikir::Plugin";

=head1 NAME

Siikir::Plugin::Search - Helper to search users!

=cut

sub init {
	my $self = shift;

	$self->debug("User plugin loaded!");
	$self->requires(qw(User Photo Profile));
}

=head1 METHODS

=head2 void buildCache ()

To speed up searches, all user info is stored in a search cache, in the DB as
C<search/cache>. This cache is a hash of user IDs mapped to their geographic
coordinates and some details for the search result (their name, age, profile
photo, etc.)

This method should be called every time profile information changes that would
affect their search result (i.e. location changes, picture changes, etc.)

=cut

sub buildCache {
	my $self = shift;

	$self->debug("Building search cache...");

	# Get all the users' IDs.
	my $ids = $self->Master->User->listUsers();
	my @profiles = ();
	foreach my $id (@{$ids}) {
		my $profile = $self->Master->Profile->getProfile($id);
		next unless defined $profile; # Skip deleted users.
		push (@profiles, $profile);
	}

	# Start building the cache.
	my $cache = {
		locations => {}, # users with known locations
		unknown   => {}, # users with undefined locations
	};

	foreach my $profile (@profiles) {
		my $id    = $profile->{userid};
		my $photo = $self->Master->Photo->getProfilePhoto($id);

		# What cache do we put them into?
		my $place = "unknown";
		my ($lat,$lon);
		if ($profile->{'geoapi'} eq "true" && $profile->{'gps-latitude'} && $profile->{'gps-longitude'}) {
			# They have a GPS location; this overrides their zip location.
			$place = "locations";
			$lat   = $profile->{'gps-latitude'};
			$lon   = $profile->{'gps-longitude'};
		}
		elsif ($profile->{'zip-latitude'} || $profile->{'zip-longitude'}) {
			# We have their coordinates based on their zipcode.
			$place = "locations";
			$lat   = $profile->{'zip-latitude'};
			$lon   = $profile->{'zip-longitude'};
		}

		# Store their profile photo, display name and "tag line" (18 / male / etc)
		my $picture = defined $photo ? $photo->{tiny} : '';
		my $name    = $profile->{displayname};
		my $tag     = $profile->{age}
			. ($profile->{gender} ? " / $profile->{gender}" : "")
			. ($profile->{orientation} ? " / $profile->{orientation}" : "");

		# Don't show pending-approval pics.
		if ($photo->{flagged} && !$photo->{approved}) {
			$picture = '';
		}

		# Place them into the cache.
		$cache->{$place}->{$id} = {
			name      => $name,
			username  => $profile->{username},
			userid    => $profile->{userid},
			tag       => $tag,
			photo     => $picture,
			latitude  => $lat,
			longitude => $lon,
		};
	}

	# Write the cache.
	$self->Master->JsonDB->writeDocument("search/cache", $cache);
	return 1;
}

=head2 data search (hash params)

To document.

Params:

  type:     Search type (nearby, custom)
  seeker:   User ID of the searcher, or 0 for guest search
  offset:   Offset of results to return (starts at 0)
  count:    Number of results to return, after the offset
  zipcode:  Reference zipcode (to search by specific location)
  distance: Maximum distance to search, in miles

=cut

sub search {
	my ($self,%params) = @_;

	# Expire old volatile links.
	$self->Master->User->expireVolatile();

	my $type   = $params{type};
	my $seeker = $params{seeker};
	my $count  = $params{count}  || 16;
	my $start  = $params{offset} || 0;
	$start *= $count;
	my $me     = {}; # The user's profile

	# Do we have a seeker?
	if ($self->Master->User->userExists(id => $seeker)) {
		$me = $self->Master->Profile->getProfile($seeker);
	}

	# If we don't have a search cache, build it now.
	if (!$self->Master->JsonDB->documentExists("search/cache")) {
		$self->buildCache();
	}

	# Get all profiles of all users.
	my $cache = $self->Master->JsonDB->getDocument("search/cache");

	# What type of search?
	if ($type eq "nearby") {
		# Test how far each user is from the seeker.
		# First make sure we know where the seeker is!
		my ($lat,$long);
		if ($me->{'geoapi'} eq "true" && $me->{'gps-latitude'} && $me->{'gps-longitude'}) {
			# We have GPS coords!
			$lat  = $me->{'gps-latitude'};
			$long = $me->{'gps-longitude'};
		}
		elsif ($me->{'zip-latitude'} && $me->{'zip-longitude'}) {
			# We have coords. Good!
			$lat  = $me->{'zip-latitude'};
			$long = $me->{'zip-longitude'};
		}
		elsif ($me->{zipcode}) {
			# We can get the coords.
			my $data = Siikir::Util::getZipcode($me->{zipcode});
			$lat  = $data->{latitude};
			$long = $data->{longitude};
		}
		elsif ($params{zipcode}) {
			# We can get the coords.
			my $data = Siikir::Util::getZipcode($params{zipcode});
			$lat  = $data->{latitude};
			$long = $data->{longitude};
		}
		else {
			# We can't help them.
			return {
				error => "Can't determine your location. Please enter a zipcode to search nearby.",
			};
		}

		# Count the number of online users.
		my $online_count = 0;

		# Start on that map.
		my $distances = {};
		foreach my $id (keys %{$cache->{locations}}) {
			my $user = $cache->{locations}->{$id};

			# Set their online status.
			$user->{online} = $self->Master->User->isOnline($user->{userid});
			$online_count++ if $user->{online};

			# Are we SEARCHING for online users only?
			if ($params{online} && !$user->{online}) {
				next;
			}

			# Calculate and store the distance.
			my $distance = Siikir::Util::getDistance($lat, $long, $user->{latitude}, $user->{longitude});
			if (!exists $distances->{$distance}) {
				$distances->{$distance} = [];
			}
			push (@{$distances->{$distance}}, $user);
		}

		# Sort the results. Make volatile links to profiles.
		my @results;
		foreach my $distance (sort { $a <=> $b } keys %{$distances}) {
			foreach my $user (@{$distances->{$distance}}) {
				# Skip blocked.
				if ($self->Master->User->isBlocked($seeker, $user->{userid}) || $self->Master->User->isBlocked($user->{userid}, $seeker)) {
					next;
				}
				$user->{distance} = $distance <= 1 ? "&lt; 1 mile away" : int($distance) . " miles away";
				push (@results, $user);
			}
		}
		foreach my $id (keys %{$cache->{unknown}}) {
			my $user = $cache->{unknown}->{$id};
			# Skip blocked.
			if ($self->Master->User->isBlocked($seeker, $user->{userid}) || $self->Master->User->isBlocked($user->{userid}, $seeker)) {
				next;
			}
			$user->{distance} = "Unknown distance";

			# Is this unknown user online?
			$user->{online} = $self->Master->User->isOnline($user->{userid});
			$online_count++ if $user->{online};

			# Are we SEARCHING for online users only?
			if ($params{online} && !$user->{online}) {
				next;
			}

			push (@results, $user);
		}

		# Find out how many pages of results we need.
		my $total = scalar(@results);
		my $pages = $total / $count;
		if ($pages =~ /\./) {
			$pages = int($pages) + 1;
		}
		$pages = 1 if $pages == 0;

		# Trim for the offset.
		my $trim = $start;
		while ($trim > 0) {
			shift(@results);
			$trim--;
		}
		if (scalar(@results) > $count) {
			splice(@results, $count); # Trim off the end
		}

		# Make up volatile links for all the visible search results.
		foreach my $res (@results) {
			$res->{link} = $self->Master->User->generateVolatile($res->{userid}, 1);
		}

		my $currentPage = $params{offset} + 1;
		if ($currentPage =~ /\./) {
			$currentPage = int($currentPage) + 1;
		}

		return {
			status  => "OK",
			offset  => $start,
			count   => $count,
			total   => $total,
			page    => $currentPage,
			pages   => $pages,
			online  => $online_count,
			results => [ @results ],
		};
	}
}

1;
