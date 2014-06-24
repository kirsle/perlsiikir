package Siikir::Controller::account::settings;

use strict;
use Siikir::Util;

sub process {
	my ($self, $vars, $url) = @_;

	# Only bother if they're logged in.
	if (!$vars->{login}) {
		$self->Master->CGI->redirect("/account/login?return=/account/settings");
		return $vars;
	}

	$self->Master->loadPlugin("Profile");
	$vars->{profile} = $self->Master->Profile->getProfile($vars->{uid});

	# Handle actions that take place within the settings page.
	my $action = scalar @{$url} ? $url->[0] : "index";
	$vars->{action} = $action;

	# Handle actions.
	if ($action eq "username") {
		# Changing their username.
		my $go = scalar @{$url} >= 2 ? $url->[1] : "";
		if ($go eq "go") {
			# They provided their password and desired username.
			my $pass = $vars->{param}->{password} || '';
			my $user = Siikir::Util::stripUsername($vars->{param}->{username}) || '';

			# Verify their password first.
			my $auth = $self->Master->User->login(
				$vars->{account}->{username},
				$pass,
			);
			if (!$auth) {
				push (@{$vars->{errors}}, "Your password was incorrect. Please try again.");
			}

			# Test if their new user exists.
			my $exists = $self->Master->User->userExists(name => $user);
			if ($exists) {
				push (@{$vars->{errors}}, "The requested username \"$user\" is not available for use.");
			}

			# Are we ok to go?
			if (scalar @{$vars->{errors}} == 0 && !$exists) {
				# Change the username.
				my $success = $self->Master->User->changeUsername ($vars->{uid}, $user);
				if ($success) {
					# Update some TT things.
					$vars->{account}->{profile}->{username} = $user;
					$vars->{success} = 1;
				}
				else {
					$vars->{errors} = [ "Failed to change your user name: $@" ];
				}
			}
		}
	}
	elsif ($action eq "password") {
		# Changing their password.
		my $go = scalar @{$url} >= 2 ? $url->[1] : "";
		if ($go eq "go") {
			my $old = $vars->{param}->{current} || '';
			my $pass = $vars->{param}->{new} || '';
			my $conf = $vars->{param}->{confirm} || '';

			# Verify their old pass first.
			my $auth = $self->Master->User->login (
				$vars->{account}->{username},
				$old,
			);
			if (!$auth) {
				push (@{$vars->{errors}}, "Your old password wasn't correct. Please try again.");
				return $vars;
			}

			# Validate the password.
			if (length $pass < 5) {
				push (@{$vars->{errors}}, "Please use a longer password.");
				return $vars;
			}
			if ($pass ne $conf) {
				push (@{$vars->{errors}}, "Your new password and confirmation don't match.");
				return $vars;
			}

			# Change their password.
			my $success = $self->Master->User->changePassword ($vars->{uid}, $pass);
			if ($success) {
				$vars->{success} = 1;
			}
			else {
				$vars->{errors} = [ "Failed to change your password: $@" ];
			}
		}
	}
	elsif ($action eq "blocked") {
		# Viewing your blocked list.
		$vars->{photopub} = $self->Master->Photo->http();
		$vars->{cache} = {}; # User data to show.
		foreach my $block (@{$vars->{account}->{blocked}}) {
			my $profile = $self->Master->Profile->getProfile($block);
			my $photo   = $self->Master->Photo->getProfilePhoto($block);
			$profile->{photo} = $photo;
			$vars->{cache}->{$block} = $profile;
		}
	}
	elsif ($action eq "block") {
		# Blocking a user.
		my $user = $vars->{param}->{who};
		$user = $self->Master->User->resolveVolatile($user, 1);
		if (!defined $user) {
			return $self->showError($vars,"Your volatile link has expired. You can't block this user right now. $@");
		}

		my $uid = $self->Master->User->getId($user);
		if (!$self->Master->User->userExists(id => $uid)) {
			return $self->showError("The user you're trying to block can't be found.");
		}

		# Unblock instead?
		if ($vars->{param}->{unblock}) {
			if (!$self->Master->User->unblockUser($vars->{uid}, $uid)) {
				return $self->showError("Failed to unblock this user: $@");
			}
		}
		else {
			if (!$self->Master->User->blockUser($vars->{uid}, $uid)) {
				return $self->showError("Failed to block this user: $@");
			}
		}
	}

	return $vars;
}

1;
