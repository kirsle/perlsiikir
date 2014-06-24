package Siikir::Controller::account::register;

use strict;
use Siikir::Util;

sub process {
	my ($self, $vars, $url) = @_;

	# We need the Profile plugin.
	$self->Master->loadPlugin("Profile");

	# Did they submit the form?
	my $action = scalar(@{$url}) ? $url->[0] : "index";

	# What was their action?
	if ($action eq "continue") {
		# They're submitting the sign-up form!
		my $username = Siikir::Util::stripUsername($vars->{param}->{username});
		my $pass1    = $vars->{param}->{password};
		my $pass2    = $vars->{param}->{confirm};
		my $month    = $vars->{param}->{month};
		my $day      = $vars->{param}->{day};
		my $year     = $vars->{param}->{year};
		my $name     = $vars->{param}->{name};
		my $email    = $vars->{param}->{email};
		my $gender   = $vars->{param}->{gender};
		my $dob      = Siikir::Util::formatDOB($year, $month, $day);
		my $age      = Siikir::Util::getAge($dob);
		my $zipcode  = $vars->{param}->{zipcode};
		my $time     = $vars->{param}->{timezone};
		my $geo      = $vars->{param}->{geoapi} eq "true" ? "true" : "";

		# Look for traps.
		my $trap1 = $vars->{param}->{website} || "";
		my $trap2 = $vars->{param}->{nick} || "";
		my $trap3 = $vars->{param}->{comment} || "";
		if ($trap1 ne 'http://' || $trap2 ne '' || $trap3 ne '') {
			push (@{$vars->{errors}}, "Registration cannot be completed at this time. Error code 504B.");
			return $vars;
		}

		# Validate things server side.
		if (length $username == 0) {
			push (@{$vars->{errors}}, "Your user name is invalid.");
		}
		elsif ($self->Master->User->userExists(name => $username)) {
			push (@{$vars->{errors}}, "That username is already in use.");
		}
		elsif (length $pass1 < 5) {
			push (@{$vars->{errors}}, "Please enter a longer password.");
		}
		elsif ($pass1 ne $pass2) {
			push (@{$vars->{errors}}, "Your passwords don't match.");
		}
		elsif ($age < 18) {
			push (@{$vars->{errors}}, "You must be at least 18 years old to use this site.");
		}
		else {
			# No problems! Register them!
			my $id = $self->Master->User->addUser (
				username => $username,
				password => $pass1,
				dob      => $dob,
			);

			# Last second error?
			if (!defined $id) {
				push (@{$vars->{errors}}, "Internal registration error: $@");
			}
			else {
				# Good, initialize their profile now.
				$self->Master->Profile->setFields($id, {
					nickname => $name,
					first_name => $name,
					email      => $email,
					gender     => $gender,
					timezone   => $time,
					zipcode    => $zipcode,
					geoapi     => $geo,
				});

				# All good! Log the user in!
				$self->Master->User->become($id);
				$vars->{login} = 1;
				$vars->{uid}   = $id;
				$vars->{account} = $self->Master->User->getAccount($id);

				# Show the register OK page!
				$self->Master->CGI->redirect("/account/welcome");
			}
		}
	}

	$vars->{testing} = "Action: $action";

	return $vars;
}

1;
