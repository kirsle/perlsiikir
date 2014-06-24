package Siikir::Controller::photos::view;

use strict;
use Siikir::Util;

sub process {
	my ($self, $vars, $url) = @_;

	# We need the Photo plugin.
	$self->Master->loadPlugin("Photo");
	$self->Master->loadPlugin("Profile");
	$self->Master->loadPlugin("Comment");
	$vars->{photopub} = $self->Master->Photo->http();

	# The URL should consist of the user ID and photo ID. It can optionally have
	# the word "album" in front.
	if (scalar(@{$url}) < 2) {
		$vars->{errors} = [ "Invalid request for a photo; no photo could be found!" ];
		$vars->{style}  = "error";
		return $vars;
	}
	my $album = undef;
	if ($url->[0] eq "album") {
		# If an album is provided, use it; otherwise set it to @all@
		if (scalar @{$url} >= 3) {
			$album = $url->[2];
		}
		else {
			$album = '@all@';
		}
		shift(@{$url});
	}
	my $uid = shift(@{$url});
	my $pid = shift(@{$url});

	# Handle a volatile URL.
	$vars->{link} = $uid;
	$uid = $self->Master->User->resolveVolatile($uid);
	if (!defined $uid) {
		$vars->{errors} = [ "Could not display photos: $@" ];
		$vars->{style}  = "error";
		return $vars;
	}

	# Was their URL volatile? If so, see if they had a private photo share link.
	# If so, we'll override "context" to match the user so that private photos
	# will be shown.
	my $context = $vars->{uid};
	if ($vars->{link} =~ /^~([A-Za-z0-9]+?)$/) {
		# Expire old volatile links.
		$self->Master->User->expireVolatile();

		# Get details, it might be a private photo share link.
		my $vol = $self->Master->User->getVolatile($vars->{link});
		if (ref($vol) && exists $vol->{options}->{private} && $vol->{options}->{private} eq "private") {
			$context = $uid; # Set the context to match the photo owners so we get private pics too.
		}
	}

	$vars->{owner} = $uid;
	$uid    = $self->Master->User->getId($uid);
	$vars->{owneruid} = $uid;

	if (!defined $uid) {
		$vars->{errors} = [ "The requested username was not found on this site." ];
		$vars->{style}  = "error";
		return $vars;
	}

	# Block list.
	if ($self->Master->User->isBlocked($vars->{uid}, $uid)) {
		return $self->showError($vars, "You have blocked this user.");
	}
	elsif ($self->Master->User->isBlocked($uid, $vars->{uid})) {
		return $self->showError($vars, "The requested photo albums were not found.");
	}

	# Get the user's profile to use their name.
	$vars->{profile} = $self->Master->Profile->getProfile($uid);

	# What view?
	$vars->{display} = undef;

	my $action = scalar(@{$url}) ? $url->[0] : "index";

	# Album list view?
	if (defined $album && $album eq '@all@') {
		# Fetch the list of albums!
		my $list = $self->Master->Photo->getAlbums($uid,$context);
		if (!defined $list) {
			$list = [];
		}

		# Set the TT var.
		$vars->{albums} = $list;
		$vars->{display} = "index";
	}
	elsif (defined $album) {
		# Fetch the album.
		my $data = $self->Master->Photo->getAlbum($uid, $album, $context);
		if (!defined $data) {
			$vars->{errors} = [ "The requested photo album was not found: $@" ];
			$vars->{style} = "error";
			return $vars;
		}

		# Get the number of comments for each photo.
		foreach my $photo (@{$data}) {
			my $comments = $self->Master->Comment->getComments($uid, "photos-$album-$photo->{key}");
			$photo->{comments} = scalar keys %{$comments};
		}

		# Set the TT vars.
		$vars->{album}     = $album;
		$vars->{photos}    = $data;
		$vars->{display}   = "album";
	}
	else {
		# Photo exists?
		my $photo = $self->Master->Photo->getPhoto($uid, $pid, $context);
		if (!defined $photo) {
			$vars->{errors} = [ "The requested photo could not be found: $@" ];
			$vars->{style} = "error";
			return $vars;
		}

		# Good, store it in the TT vars.
		$vars->{photo}    = $photo;
		$vars->{display}  = "photo";

		# Set a friendly time stamp.
		$vars->{mtime} = Siikir::Time::getLocalTimestamp("Mon dd, yyyy @ H:mm AM", $photo->{uploaded}, $vars->{account}->{profile}->{timezone} || 0);
	}

	# What was their action?
	if ($action eq "comment") {
		# TODO
	}

	return $vars;
}

1;
