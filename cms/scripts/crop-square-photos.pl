#!/usr/bin/perl -w

# Re-calculae everyone's square photos.

use lib "../src";
use lib "./cms/src";
use strict;
use Siikir;
use Siikir::Util;
chdir("../..");

my $cms = Siikir->new(
	debug => 1,
	root  => "./cms",
);
$cms->loadPlugin("JsonDB");
$cms->loadPlugin("User");
$cms->loadPlugin("Photo");

# debug
$cms->Photo->cropPhoto (1, "04988746e1aca41efa8bda49e79d0a7a",
	'x' => 276,
	'y' => 96,
	'size' => 333,
);
exit(0);

my $users = $cms->User->listUsers();
foreach my $user (@{$users}) {
	print "User ID: $user\n";
	my $albums = $cms->Photo->getAlbums($user, 1);
	foreach my $album (@{$albums}) {
		print "\tAlbum: $album->{name}\n";
		my $photos = $cms->Photo->getAlbum($user, $album->{name}, 1);

		# Recalc each smaller photo.
		foreach my $photo (@{$photos}) {
			print "\t\tPhoto: $photo->{key}\n";

			# Scale each smaller size.
			foreach my $size (qw(medium small tiny avatar mini)) {
				print "\t\t\tScale to size: $size\n";
				my $name = $cms->Photo->resizePhoto ("./static/photos/$photo->{large}", $size,
					filename => $photo->{$size},
				);
			}
		}
	}
}
