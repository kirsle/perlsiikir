#!/usr/bin/perl -w

# Re-calculae everyone's mini photos.

use lib "../src";
use lib "./cms/src";
use strict;
use Siikir;
use Siikir::Util;
chdir("../..");

my $cms = Siikir->new(
	debug => $ENV{X_SIIKIR_DEBUG} || 0,
	root  => "./cms",
);
$cms->loadPlugin("JsonDB");
$cms->loadPlugin("User");
$cms->loadPlugin("Photo");

my $users = $cms->User->listUsers();
foreach my $user (@{$users}) {
	my $db = $cms->JsonDB->getDocument("photos/$user");
	foreach my $album (sort { $a cmp $b } keys %{$db->{albums}}) {
		print "User $user -> Album $album\n";

		foreach my $photo (sort { $a cmp $b } keys %{$db->{albums}->{$album}}) {
			print "\tPhoto $photo\n";
			my $path = "./static/photos/$db->{albums}->{$album}->{$photo}->{large}";
			print "\t\tLarge: $path\n";
			if (!-e $path) {
				die "Can't locate $path";
			}

			# Make the smaller photo.
			my $mini = $cms->Photo->resizePhoto($path, "mini");
			print "\t\tMini photo: $mini\n";

			$db->{albums}->{$album}->{$photo}->{mini} = $mini;
		}
	}
	$cms->JsonDB->writeDocument("photos/$user", $db);
}
