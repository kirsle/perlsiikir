package Siikir::Controller::mail::index;

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

	# What box are we viewing?
	my $box    = scalar @{$url} ? $url->[0] : "inbox";
	my $action = scalar @{$url} > 1 ? $url->[1] : "";
	my $mid    = scalar @{$url} > 2 ? $url->[2] : -1;
	$vars->{mailbox} = $box;
	$vars->{action}  = $action;

	# Get their mailboxes.
	$vars->{mailboxes} = $self->Master->Messaging->getMailboxes($vars->{uid});

	# Select the messages to show. Paginate them.
	my $page = $vars->{param}->{page} || 0;
	if ($page =~ /^\d+$/) {
		$page--;
		$page = 0 if $page < 0;
	}
	else {
		$page = 0;
	}
	$vars->{messages}  = [];
	$vars->{start} = $page * 10;
	$vars->{end}   = $vars->{start} + 10;
	$vars->{end}   = scalar @{$vars->{mailboxes}->{$box}} if $vars->{end} > scalar @{$vars->{mailboxes}->{$box}};
	$vars->{total} = scalar @{$vars->{mailboxes}->{$box}} - 1;
	$vars->{page}  = $page + 1;
	$vars->{pages} = $vars->{total} / 10;
	if ($vars->{pages} =~ /\./) {
		$vars->{pages} = int($vars->{pages} + 1);
	}
	for (my $i = $vars->{start}; $i < $vars->{end} && $i < scalar @{$vars->{mailboxes}->{$box}}; $i++) {
		my $msg = $vars->{mailboxes}->{$box}->[$i];

		# Skip messages with blocked users.
		my $dir = $box eq "inbox" ? "from" : "to";
		if ($self->Master->User->isBlocked($vars->{uid}, $msg->{$dir}) || $self->Master->User->isBlocked($msg->{$dir}, $vars->{uid})) {
			next;
		}
		push (@{$vars->{messages}}, $msg);
	}

	# Read a specific message?
	if ($action eq "read") {
		# Find the message.
		my @new = ();
		foreach my $message (@{$vars->{mailboxes}->{$box}}) {
			unless ($message->{time} == $mid) {
				push (@new, $message);
				next;
			}

			# Found it! Mark it read now.
			$message->{read} = 1;
			push (@new, $message);
			$vars->{message} = $message;
		}

		if (!$vars->{message}) {
			$vars->{errors} = [ "The message could not be found!" ];
			$vars->{style} = "error";
			return $vars;
		}
		else {
			# Save the changes.
			$self->Master->Messaging->setMessages($vars->{uid}, $box, \@new);
		}
	}
	elsif ($vars->{param}->{action} eq "delete") {
		# List the deleted messages.
		my @victims = (
			ref($vars->{param}->{mailid}) eq "ARRAY" ? @{$vars->{param}->{mailid}} : $vars->{param}->{mailid}
		);
		my %map = map { $_ => 1 } @victims;

		my @new = ();
		foreach my $message (@{$vars->{mailboxes}->{$box}}) {
			next if exists $map{ $message->{time} };
			push (@new, $message);
		}

		$self->Master->Messaging->setMessages($vars->{uid}, $box, \@new);
		$self->Master->CGI->redirect("/mail" . ($box eq "sent" ? "/sent" : ""));
	}

	# Preload all profiles and photos.
	$vars->{cache} = {};
	foreach my $message (@{$vars->{mailboxes}->{$box}}) {
		# Pretty-format the time.
		$message->{time_pretty} = Siikir::Time::getLocalTimestamp("Mon, dd yyyy @ H:mm AM", $message->{time}, $vars->{account}->{profile}->{timezone} || 0);
		foreach my $sender (qw(to from)) {
			my $from = $message->{$sender};
			next if exists $vars->{cache}->{$from};
			my $profile = $self->Master->Profile->getProfile($from);
			my $photo   = $self->Master->Photo->getProfilePhoto($from);

			# Hide pending profile photos.
			if (defined $photo && $photo->{flagged} && !$photo->{approved}) {
				$photo = undef;
			}

			# Does the user want to be unlinkable?
			my $link;
			if (defined $profile->{privacy} && $profile->{privacy} =~ /unlinkable/i) {
				$link = $self->Master->User->generateVolatile($from, 0);
			}

			# What size photo? Avatar for web, mini for mobile.
			my $tsize = "avatar";
			if ($self->Master->Mobile->isMobile()) {
				$tsize = "mini";
			}

			$vars->{cache}->{$from} = {
				name     => $profile->{displayname},
				username => $profile->{username},
				photo    => $photo ? $photo->{$tsize} : "",
				link     => defined $link ? $link : $profile->{username},
			};
		}
	}

	return $vars;
}

1;
