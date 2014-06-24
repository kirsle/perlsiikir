package Siikir::Controller::comment;

use strict;
use Digest::MD5 qw(md5_hex);
use Siikir::Util;

sub process {
	my ($self, $vars, $url) = @_;

	# We need the Profile plugin.
	$self->Master->loadPlugin("Comment");
	$self->Master->loadPlugin("User");
	$self->Master->loadPlugin("Profile");
	$self->Master->loadPlugin("Photo");
	$self->Master->loadPlugin("Emoticons");
	$self->Master->loadPlugin("Facebook");
	$vars->{photopub} = $self->Master->Photo->http();

	# Just requesting the privacy page?
	if (scalar @{$url} && $url->[0] eq "privacy") {
		$vars->{show_privacy} = 1;
		return $vars;
	}

	# Facebook Graph?
	my $fb = $self->Master->Facebook->appinfo();
	if (defined $fb) {
		$vars->{fb_graph} = 1;
		$vars->{fb_app_id}  = $fb->{app_id};
		$vars->{fb_secret}  = $fb->{secret};
	}

	my $action = $vars->{param}->{do} || "index";
	my $owner  = $vars->{param}->{user} || $vars->{param}->{u};
	my $thread = $vars->{param}->{thread};
	$vars->{action} = $action;

	# Missing vars?
	unless ($action eq "unsubscribe") {
		if (!$owner || !$thread) {
			return $self->showError($vars, "An unknown and improbable error has occurred. Please try again later.");
		}
	}

	# Sanitize all inputs.
	foreach my $key (keys %{$vars->{param}}) {
		$vars->{param}->{$key} = Siikir::Util::stripHTML($vars->{param}->{$key});
	}
	$vars->{param}->{preview} = $vars->{param}->{message} || "";
	$vars->{param}->{preview} =~ s/\n/<br>/ig;
	$vars->{param}->{preview} =~ s/[\x0D\x0A]+//g;
	$vars->{param}->{preview} = $self->Master->Emoticons->render($vars->{param}->{preview});

	# Are they subscribing?
	if ($vars->{param}->{subscribe} eq "true") {
		# If logged in, get their contact e-mail.
		if ($vars->{login}) {
			$vars->{param}->{contact} = $vars->{account}->{profile}->{email};
		}

		# Validate.
		if ($vars->{param}->{contact} !~ /^.+\@.+\..+$/) {
			return $self->showError($vars, "Your subscription e-mail isn't a valid e-mail address.");
		}
	}

	# Actions.
	if ($action eq "preview") {
		# Verify the spam trap.
		my $trap1 = $vars->{param}->{website};
		my $trap2 = $vars->{param}->{email};
		if ($trap1 ne 'http://' || $trap2 ne '') {
			return $self->showError($vars, "You failed the spam bot trap.");
		}

		# Fucking spammers. fuck!
		if (($vars->{param}->{message} =~ /@/ && $vars->{param}->{message} =~ /\.com|\.\s+com|\.ru/) ||
		$vars->{param}->{message} =~ /yahoo|hotmail|rocketmail|spell caster/i) {
			return $self->showError($vars, "An unknown error has occurred. Please try again.");
		}

		# Message is required.
		if (!length $vars->{param}->{message}) {
			return $self->showError($vars, "You must provide a message with your comment.");
		}
	}
	elsif ($action eq "post") {
		# Message is required.
		if (!length $vars->{param}->{message}) {
			return $self->showError($vars, "You must provide a message with your comment.");
		}

		# Tag the post for whether they used Tor.
		if (Siikir::Util::isTor()) {
			$vars->{param}->{name} .= " (via Tor)";
			$vars->{param}->{message} .= "<p>"
				. "<em>This comment was submitted from behind "
				. "<a href=\"https://www.torproject.org\">The Onion Router</a>.</em>";
		}

		# Post the comment. Limit image domains.
		my $image = $vars->{param}->{image} || "";
		if ($image !~ /^http:\/\/graph\.facebook\.com/i) {
			$image = "";
		}
		$self->Master->Comment->addComment ($owner, $thread,
			uid     => $vars->{uid},
			name    => $vars->{login} ? undef : $vars->{param}->{name},
			image   => $vars->{login} ? undef : $image,
			message => $vars->{param}->{message},
			subject => $vars->{param}->{subject},
			url     => $vars->{param}->{url},
			time    => time(),
			ip      => $ENV{REMOTE_ADDR},
		);

		# Subscribing?
		if ($vars->{param}->{subscribe} eq "true") {
			# If logged in, subscribe by user ID. Otherwise, use the e-mail.
			my $subscriber = $vars->{login} ? $vars->{uid} : $vars->{param}->{contact};
			my $ok = $self->Master->Comment->addSubscriber($owner, $thread, $subscriber);
			if (!$ok) {
				push @{$vars->{warnings}}, $@;
			}
		}
	}
	elsif ($action eq "delete") {
		# Must be the owner of the comments.
		if ($vars->{login} && ($vars->{uid} == $owner || $vars->{isAdmin})) {
			my $success = $self->Master->Comment->deleteComment ($owner, $thread, $vars->{param}->{comment});
			if (!$success) {
				return $self->showError($vars,"Failed to delete comment: $@");
			}
		}
		else {
			return $self->showError($vars,"You don't have permission to delete this comment.");
		}
	}
	elsif ($action eq "unsubscribe") {
		# From what?
		my $owner = $vars->{param}->{u} || undef;
		my $thread = $vars->{param}->{thread} || "all";
		my $email  = $vars->{param}->{email} || $vars->{param}->{who};

		# Unsubscribe them.
		if ($thread && $email) {
			my $ok = $self->Master->Comment->removeSubscriber($owner, $thread, $email);
			if (!$ok) {
				return $self->showError($vars, $@);
			}
		}
		else {
			return $self->showError($vars, "Failed to unsubscribe. Check the link and try again.");
		}
	}
	else {
		# Index: load all the existing comments.
		my $comments = $self->Master->Comment->getComments($owner, $thread);

		# Pretty-format all comment times.
		my $tz = $vars->{login} ? $vars->{account}->{profile}->{timezone} : $self->{timezone};
		$vars->{users} = {};
		foreach my $id (keys %{$comments}) {
			$comments->{$id}->{pretty_time} = Siikir::Time::getLocalTimestamp (
				"Weekday, Mon dd yyyy @ H:mm AM", $comments->{$id}->{time}, $tz
			);

			# Render emoticons.
			$comments->{$id}->{message} = $self->Master->Emoticons->render($comments->{$id}->{message});

			# If this is a site user, get their name and photo.
			if ($comments->{$id}->{uid} > 0 && !exists $vars->{users}->{ $comments->{$id}->{uid} }) {
				if ($self->Master->User->userExists(id => $comments->{$id}->{uid})) {
					my $profile = $self->Master->Profile->getProfile($comments->{$id}->{uid});
					my $photo   = $self->Master->Photo->getProfilePhoto($comments->{$id}->{uid});
					$vars->{users}->{ $comments->{$id}->{uid} } = {
						username => $profile->{username},
						name     => $profile->{displayname},
						photo    => $photo,
					};
				}
			}
		}

		$vars->{comment_id} = [ sort { $comments->{$a}->{time} <=> $comments->{$b}->{time} } keys %{$comments} ];
		$vars->{comments}   = $comments;
	}

	return $vars;
}

1;
