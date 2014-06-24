package Siikir::Controller::account::recover;

use strict;
use Digest::MD5 qw(md5_hex);
use Siikir::Util;

sub process {
	my ($self, $vars, $url) = @_;

	$self->Master->loadPlugin("User");
	$self->Master->loadPlugin("Profile");
	$self->Master->loadPlugin("Messaging");

	# Password recovery hash algo:
	# md5( salt + md5pass), using the salt/passwd from their account file.

	# Did they submit the form?
	my $action = scalar(@{$url}) ? $url->[0] : "index";
	$vars->{action} = $action;

	# What was their action?
	if ($action eq "index") {
		# The first step.
		my $forgot = $vars->{param}->{forgot} || "";

		# What did they forget?
		if ($forgot eq "username") {
			# They forgot their username. Look up users by e-mail address.
			my $email = lc($vars->{param}->{email});

			# Validate the e-mail.
			if ($email !~ /^.+?\@.+?$/) {
				return $self->showError($vars, "The e-mail address provided is incorrectly formatted.");
			}

			my $users = $self->Master->User->listUsers();
			my @match = (); # Matches
			foreach my $id (@{$users}) {
				# Get their profile.
				my $profile = $self->Master->Profile->getProfile($id);
				next unless defined $profile;

				# Look for a matching e-mail address.
				my $check = lc($profile->{email});
				if ($email eq $check) {
					# A match! Get the username now.
					my $username = $self->Master->User->getUsername($id);
					push (@match, $username);
				}
			}

			# Matches?
			if (scalar(@match)) {
				# Dispatch e-mails.
				my $body = "This is an automated e-mail from the Username Recovery feature of $vars->{sitename}. "
					. "Below you will find the username(s) associated with your e-mail address.\n\n"
					. join("\n", @match) . "\n\n"
					. "This e-mail was generated because somebody (hopefully you) has used the Username Recovery "
					. "feature on $vars->{sitename}. If you did not request this information, don't worry! The "
					. "Username Recovery feature never confirms or denies that the e-mail address actually belongs "
					. "to anybody on the site.\n\n"
					. "This e-mail was automatically generated; do not reply to it.";

				$self->Master->Messaging->email (
					email   => $email,
					subject => "Username Recovery",
					message => $body,
				);
			}

			$vars->{action} = "fuser";
		}
		elsif ($forgot eq "password") {
			# They've forgotten their password.
			my $username = Siikir::Util::stripUsername($vars->{param}->{username});

			# Validate their username.
			if (!$self->Master->User->userExists(name => $username)) {
				return $self->showError($vars, "No such user name exists on this website.");
			}

			# Look up their profile.
			my $id      = $self->Master->User->getId($username);
			my $acct    = $self->Master->User->getAccount($id);
			my $profile = $self->Master->Profile->getProfile($id);
			if (!defined $profile) {
				return $self->showError($vars, "There is no profile information for that user name.");
			}

			# Valid e-mail on file?
			my $email = $profile->{email};
			if ($email =~ /^.+?\@.+?$/) {
				# Generate the recovery string.
				my $recovery = md5_hex($acct->{salt} . $acct->{password});

				# Dispatch a recovery e-mail.
				$self->Master->Messaging->email (
					email   => $email,
					subject => "Password Recovery",
					message => "Hello $username!\n\n"
						. "This e-mail was automatically generated in response to a Password Recovery request on $vars->{sitename}. "
						. "In order to set a new password for your account ($username), please click on the link below:\n\n"
						. "http://$ENV{SERVER_NAME}/account/recover/$username/$recovery\n\n"
						. "Note: this e-mail was generated because somebody (hopefully you) has used the Password Recovery feature. "
						. "If you did not do this, don't worry - just ignore this e-mail; your account is still safe!\n\n"
						. "This e-mail was automatically generated - do not reply to it.",
				);
				$vars->{success} = 1;
			}
			else {
				$vars->{success} = 0;
			}

			$vars->{action} = "fpass";
		}
	}
	else {
		# They should have clicked a recovery link to get to this point.
		my $username = Siikir::Util::stripUsername($action);
		my $hash     = scalar @{$url} > 1 ? $url->[1] : "";

		# Validate it.
		if (!$self->Master->User->userExists(name => $username)) {
			$self->Master->CGI->redirect("/account/recover");
			return $vars;
		}

		# Get the account to validate the recovery string.
		my $id      = $self->Master->User->getId($username);
		my $acct    = $self->Master->User->getAccount($id);
		my $profile = $self->Master->Profile->getProfile($id);
		if (!defined $profile) {
			$self->Master->CGI->redirect("/account/recover");
			return $vars;
		}

		# Generate the correct recovery string.
		my $recover = md5_hex($acct->{salt} . $acct->{password});

		# Validate it.
		if ($hash ne $recover) {
			return $self->showError($vars, "An unknown error has occurred. Please try the Password Recovery again from the beginning.");
		}

		$vars->{action}   = "reset";
		$vars->{username} = $username;
		$vars->{hash}     = $hash;

		# Submitting the form?
		if (exists $vars->{param}->{password}) {
			my $pw1 = $vars->{param}->{password};
			my $pw2 = $vars->{param}->{confirm};

			# Validate.
			if (!length $pw1) {
				return $self->showError($vars, "You must enter a password. Please go back and try again.");
			}
			elsif ($pw1 ne $pw2) {
				return $self->showError($vars, "Your passwords do not match. Please go back and try again.");
			}

			# And reset their password!
			$self->Master->User->changePassword($id, $pw1);
			$vars->{success} = 1;
		}
	}

	return $vars;
}

1;
