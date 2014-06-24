package Siikir::Controller::mail::compose;

use strict;
use Siikir::Util;

sub process {
	my ($self, $vars, $url) = @_;

	# We need the Profile plugin.
	$self->Master->loadPlugin("Profile");
	$self->Master->loadPlugin("Photo");
	$self->Master->loadPlugin("User");
	$self->Master->loadPlugin("Messaging");
	$vars->{photopub} = $self->Master->Photo->http();

	# Must be logged in.
	if (!$vars->{login}) {
		$self->Master->CGI->redirect("/account/login?return=/mail");
		return $vars;
	}

	# Are we composing to a specific user?
	my $to = $vars->{param}->{to} || "";
	$vars->{link} = $to;
	if (!length $to) {
		$vars->{errors} = [ "No user specified to send mail to." ];
		$vars->{style}  = "error";
		return $vars;
	}

	# Volatile target.
	$to = $self->Master->User->resolveVolatile($to);
	if (!defined $to) {
		$vars->{errors} = [ "You can't send mail: $@" ];
		$vars->{style}  = "error";
		return $vars;
	}

	my $uid = $self->Master->User->getId($to);
	if (!defined $uid) {
		$vars->{errors} = [ "That user doesn't exist." ];
		$vars->{style}  = "error";
		return $vars;
	}

	# Get the user's profile and photo.
	$vars->{profile} = $self->Master->Profile->getProfile($uid);
	$vars->{photo}   = $self->Master->Photo->getProfilePhoto($uid);

	# Did they submit the form?
	my $action = scalar(@{$url}) ? $url->[0] : "index";
	if ($action eq "send") {
		# Attempting to send the message.
		my $from    = $vars->{uid};
		my $subject = $vars->{param}->{subject};
		my $body    = $vars->{param}->{message};

		# Send the message.
		my $success = $self->Master->Messaging->sendMessage(
			from   => $from,
			to     => $uid,
			subject => $subject,
			message => $body,
		);
		if (!$success) {
			push (@{$vars->{errors}}, "Failed to send message: $@");
		}

		$vars->{success} = $success;
	}

	return $vars;
}

1;
