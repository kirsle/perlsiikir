package Siikir::Controller::account::login;

use strict;
use Siikir::Util;

sub process {
	my ($self, $vars, $url) = @_;

	# Did they submit the form?
	my $action = scalar(@{$url}) ? $url->[0] : "index";

	# What was their action?
	if ($action eq "go") {
		# They're submitting the sign-up form!
		my $username = Siikir::Util::stripUsername($vars->{param}->{username});
		my $password = $vars->{param}->{password};

		# Try to log them in.
		if (!$self->Master->User->userExists(name => $username)) {
			push (@{$vars->{errors}}, "That user name wasn't found.");
		}
		else {
			my $id = $self->Master->User->login($username, $password);
			if (!defined $id) {
				push (@{$vars->{errors}}, "Authentication has failed. Please try again.", $@);
			}
			else {
				# Good!
				$self->Master->User->become($id);
				$vars->{login} = 1;
				$vars->{uid}   = $id;
				$vars->{account} = $self->Master->User->getAccount($id);
				$vars->{account}->{profile} = $self->Master->Profile->getProfile($id);
				$vars->{unreadmsg} = $self->Master->Messaging->getUnread($id);
				$vars->{isAdmin}   = $self->Master->User->isAdmin($id);

				# Redirect them.
				my $dest = "/";
				if ($vars->{param}->{return}) {
					# They have a destination already.
					$dest = $vars->{param}->{return};
					if ($dest !~ /^\//) {
						# This isn't a local path!
						$dest = "/";
					}
				}

				$self->Master->CGI->redirect($dest);
			}
		}
	}

	return $vars;
}

1;
