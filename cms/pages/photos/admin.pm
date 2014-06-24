package Siikir::Controller::photos::admin;

use strict;
use Siikir::Util;
use Digest::MD5 qw(md5_hex);

sub process {
	my ($self, $vars, $url) = @_;

	# We need the Photo plugin.
	$self->Master->loadPlugin("Photo");
	$vars->{photopub} = $self->Master->Photo->http();
	$vars->{adultallowed} = $self->Master->Photo->adultAllowed();

	# The first item in the URL scheme should be an action, e.g. setdefault,
	# setcover, edit, delete. Once we figure out the photo ID, be sure the user
	# owns it too! Actually, abort here if the user isn't even logged in.
	if (!$vars->{login}) {
		$self->Master->CGI->redirect("/account/login");
		return $vars;
	}

	my $action = "index";
	my $album  = undef;
	my $uid    = $vars->{uid};
	my $pid    = undef;
	if (scalar @{$url} > 0) {
		$action = $url->[0];
		if ($action eq "setdefault") {
			$pid = $url->[1];
		}
		elsif ($action eq "setcover") {
			$album = $url->[1];
			$pid   = $url->[2];
		}
		elsif ($action eq "crop") {
			$pid   = $url->[1];
		}
		elsif ($action eq "edit") {
			$pid   = $url->[1];
		}
		elsif ($action eq "arrange") {
			$album = $url->[1];
		}
		elsif ($action eq "delete") {
			$pid   = $url->[1];
		}
		elsif ($action eq "private") {
			# Locking/unlocking private photo access.
		}
		elsif ($action eq "share") {
			# Sharing photos with users outside of Siikir.
		}
		else {
			$vars->{errors} = [ "Unknown administrative action." ];
			$vars->{style}  = "error";
			return $vars;
		}
	}

	# We know the PID, get the details to verify ownership.
	my $photo = undef;
	if (defined $pid) {
		$photo = $self->Master->Photo->getPhoto($vars->{uid}, $pid, $vars->{uid});
	}
	if (!defined $photo && ($action ne "arrange" && $action ne "private" && $action ne "share")) {
		$vars->{errors} = [ "You don't own this photo." ];
		$vars->{style}  = "error";
		return $vars;
	}

	# Keep track of the photo for TT.
	$vars->{photo} = $photo;

	# Handle the actions.
	$vars->{action} = $action;
	if ($action eq "setdefault") {
		# Set the profile picture.
		$vars->{success} = $self->Master->Photo->setDefault($uid, $pid);
		if (!$vars->{success}) {
			$vars->{errors} = [ $@ ];
		}
	}
	elsif ($action eq "setcover") {
		# Set the album cover picture.
		$vars->{success} = $self->Master->Photo->setCover($uid, $album, $pid);
		if (!$vars->{success}) {
			$vars->{errors} = [ $@ ];
		}
	}
	elsif ($action eq "crop") {
		# Saving the crop?
		if ($vars->{param}->{action} eq "doCrop") {
			my $x    = $vars->{param}->{x};
			my $y    = $vars->{param}->{y};
			my $size = $vars->{param}->{size};
			$self->Master->Photo->cropPhoto ($uid, $pid,
				'x' => $x,
				'y' => $y,
				'size' => $size,
			);
			$vars->{photo} = $self->Master->Photo->getPhoto($vars->{uid}, $pid, $vars->{uid});
		}
	}
	elsif ($action eq "edit") {
		# Editing? Make up a weak unique key. We use the file name or URL given at the
		# time of upload as part of the hash.
		$vars->{hash} = md5_hex($uid . $pid . $vars->{photo}->{name});

		# Saving the photo?
		if (scalar @{$url} > 2 && $url->[2] eq "save") {
			# Collect query params.
			my $caption = $vars->{param}->{caption} || "";
			my $private = $vars->{param}->{private} eq "true" ? 1 : 0;
			my $adult   = $vars->{param}->{adult}   eq "true" ? 1 : 0;
			my $hash    = $vars->{param}->{hash} || "";

			# Verify the hash code.
			if ($hash eq $vars->{hash}) {
				# Update the photo.
				$vars->{success} = $self->Master->Photo->updatePhoto ($uid, $pid,
					caption => $caption,
					private => $private,
					adult   => $adult,
				);
				if (!$vars->{success}) {
					$vars->{errors} = [ $@ ];
				}
			}
			else {
				$vars->{errors} = [ "Failed to update photo do to a checksum failure." ];
				$vars->{style}  = "error";
			}
		}
	}
	elsif ($action eq "arrange") {
		# Arrange photos.
		$vars->{album} = $album;

		# Fetch their album.
		my $data = $self->Master->Photo->getAlbum($uid, $album, $uid);
		if (!defined $data) {
			return $self->showError($vars, "The requested album was not found: $@");
		}

		# Set the TT vars.
		$vars->{photopub} = $self->Master->Photo->http();
		$vars->{photos} = $data;

		# Saving?
		if ($vars->{param}->{do} eq "arrange") {
			# The photo list.
			my @list = split(/\;/, $vars->{param}->{order});

			# Apply the arrangement.
			my $ok = $self->Master->Photo->arrangePhotos($uid, $album, \@list);
			if (!defined $ok) {
				return $self->showError($vars, "Failed to rearrange your photos: $@");
			}
			else {
				$vars->{success} = 1;
			}
		}
	}
	elsif ($action eq "delete") {
		# Deleting? Make up that key again.
		$vars->{hash} = md5_hex("delete" . $uid . $pid . $vars->{photo}->{name});

		# Deleting for sure?
		if (scalar @{$url} > 2 && $url->[2] eq "confirm") {
			# Verify the hash.
			my $hash = $vars->{param}->{hash} || "";
			if ($hash eq $vars->{hash}) {
				# Go ahead with the deletion.
				$vars->{success} = $self->Master->Photo->deletePhoto ($uid, $pid);
				if (!$vars->{success}) {
					$vars->{errors} = [ $@ ];
				}
			}
			else {
				$vars->{errors} = [ "Failed to delete photo due to a checksum failure." ];
				$vars->{style}  = "error";
			}
		}
	}
	elsif ($action eq "private") {
		# Private photo lock/unlock.
		my $lock = $vars->{param}->{do};
		my $for  = $vars->{param}->{for};

		# Resolve volatile links.
		if ($lock ne "list") {
			$for = $self->Master->User->resolveVolatile($for);
			if (!defined $for) {
				return $self->showError($vars, "Can't resolve user from volatile link: $@");
			}

			# Resolve the ID of "for".
			$for = $self->Master->User->getId($for);
			$vars->{profile} = $self->Master->Profile->getProfile($for);

			# Are we unlocking?
			if ($lock eq "unlock") {
				# Unlock the photos.
				$self->Master->Photo->unlockPrivate($uid, $for);
			}
			elsif ($lock eq "lock") {
				# Lock them back up.
				$self->Master->Photo->lockPrivate($uid, $for);
			}
		}
		elsif ($lock eq "list") {
			# List who can see my photos.
			my $list = $self->Master->Photo->unlockedList($uid);
			$vars->{viewers} = [];
			foreach my $id (@{$list}) {
				# Get this user's profile and photo.
				my $profile = $self->Master->Profile->getProfile($id) or next;
				my $photo   = $self->Master->Photo->getProfilePhoto($id);
				$profile->{photo} = $photo->{tiny};
				push (@{$vars->{viewers}}, $profile);
			}
		}
		else {
			$vars->{errors} = [ "Unknown command given to lock/unlock photos." ];
			$vars->{style}  = "error";
		}
	}
	elsif ($action eq "share") {
		my $do = $vars->{param}->{do};

		my $lifetime = $vars->{param}->{lifetime};
		if ($lifetime =~ /^\d+$/) {
			$lifetime *= 60; # Make into minutes
		}

		# Making a private link?
		if ($do eq "private") {
			# Generate a volatile link which allows access to private photos.
			$vars->{volatile} = $self->Master->User->generateVolatile($uid, 1,
				private => "private",
				expires => $lifetime,
			);
		}
	}

	return $vars;
}

1;
