#!/usr/bin/perl -w

# Re-calculae everybody' locations from their zipcodes.

use lib "../src";
use strict;
use Siikir;

my $cms = Siikir->new(
	debug => $ENV{X_SIIKIR_DEBUG} || 0,
	root  => "..",
);
$cms->loadPlugin("User");
$cms->loadPlugin("Profile");

my $users = $cms->User->listUsers();
foreach my $id (@{$users}) {
	my $profile = $cms->Profile->getProfile($id);
	next unless $profile->{zipcode};

	my $calc = Siikir::Util::getZipcode($profile->{zipcode});
	next unless defined $calc;
	print "User ID: $id ($profile->{username})\n"
		. "\tZip: $profile->{zipcode}   Locaion: $calc->{latitude}, $calc->{longitude}\n";

	# Save their profile.
	$cms->Profile->setFields($id, {
		'zip-latitude' => $calc->{latitude},
		'zip-longitude' => $calc->{longitude},
	});
}
