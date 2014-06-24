package Siikir::Controller::profile::view;

use strict;
use Siikir::Util;

sub process {
	my ($self, $vars, $url) = @_;

	# We need the Profile plugin.
	$self->Master->loadPlugin("Profile");
	$self->Master->loadPlugin("Photo");
	$self->Master->loadPlugin("Hotlist");
	$vars->{photopub} = $self->Master->Photo->http();

	# What user are they viewing?
	my $user = scalar @{$url} ? $url->[0] : "";
	if (length $user == 0) {
		# Assume the local user.
		if ($vars->{login}) {
			$user = $vars->{uid};
		}
		else {
			return $self->showError($vars, "Can't load profile: no user was specified.");
		}
	}

	# Store the user format used in the link.
	$vars->{link} = $user;

	# Is it a volatile link?
	$user = $self->Master->User->resolveVolatile($user);
	if (!defined $user) {
		return $self->showError($vars, "Couldn't display this profile: $@");
	}

	# Resolve to a user ID.
	$user = $self->Master->User->getId($user);

	# Blocking?
	if ($self->Master->User->isBlocked($vars->{uid}, $user)) {
		return $self->showError($vars, "You have blocked this user.");
	}
	if ($self->Master->User->isBlocked($user, $vars->{uid})) {
		return $self->showError($vars, "The requested profile was not found.");
	}

	# Get their profile.
	$vars->{profile} = $self->Master->Profile->getProfile($user);
	if (!defined $vars->{profile}) {
		return $self->showError($vars, "The requested profile was not found.");
	}

	# User seems to exist. Get their profile photo.
	$vars->{photo} = $self->Master->Photo->getProfilePhoto($user);

	# Check whether we have unlocked our private photos for this user.
	$vars->{unlocked} = $self->Master->Photo->privatePermission($vars->{uid}, $user);

	# Check whether they're on our hot list.
	$vars->{hotlist} = $self->Master->Hotlist->onHotlist($user, "forward", $vars->{uid});

	return $vars;
}

1;
