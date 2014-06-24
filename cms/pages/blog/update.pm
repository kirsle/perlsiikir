package Siikir::Controller::blog::update;

use strict;
use Time::Local;
use Siikir::Util;
use Siikir::Time;

sub process {
	my ($self, $vars, $url) = @_;

	# We need the Profile plugin.
	$self->Master->loadPlugin("Profile");
	$self->Master->loadPlugin("Photo");
	$self->Master->loadPlugin("Blog");
	$vars->{photopub} = $self->Master->Photo->http();
	$vars->{avatarpub} = $self->Master->Blog->avatarHttp();

	# They must be logged in.
	if (!$vars->{login}) {
		return $self->showError($vars, "You must be logged in to do that!");
	}

	# Are they allowed?
	my $adminOnly = $self->Master->Blog->adminOnly();
	if ($adminOnly && !$self->Master->User->isAdmin($vars->{uid})) {
		return $self->showError($vars, "Only administrators can have blogs.");
	}

	# Get our avatars.
	$vars->{userpic} = $self->Master->Photo->getProfilePhoto($vars->{uid});
	$vars->{avatars} = [ $self->Master->Blog->getAvatars() ];

	# Editing an existing post?
	if ($vars->{param}->{id}) {
		my $id   = $self->Master->Blog->resolveId($vars->{uid}, $vars->{param}->{id});
		if (defined $id) {
			$vars->{id} = $id;
			my $post = $self->Master->Blog->getEntry($vars->{uid}, $vars->{param}->{id}, 1);
			$vars->{post} = $post;

			# Copy fields.
			foreach my $field (qw(subject body avatar categories privacy emoticons)) {
				$vars->{$field} = $post->{$field};
			}
			$vars->{param}->{"emoticons"} = $post->{emoticons};
			$vars->{param}->{"replies"}   = $post->{comments};

			# Dissect the time.
			my $tz = $vars->{login} ? $vars->{account}->{profile}->{timezone} : $self->{timezone};
			my $time = Siikir::Time::getLocalTimestamp(
				"mm{on}:dd:yyyy:hh:mm{in}:ss", $post->{time}, $tz
			);
			my @parts = split(/:/, $time);
			$vars->{month} = $parts[0];
			$vars->{day}   = $parts[1];
			$vars->{year}  = $parts[2];
			$vars->{hour}  = $parts[3];
			$vars->{min}   = $parts[4];
			$vars->{sec}   = $parts[5];
		}
	}

	# Get any fields from the query string.
	foreach my $field (qw(subject body avatar categories privacy emoticons replies
	month day year hour min sec no-emoticons no-replies)) {
		if (exists $vars->{param}->{$field}) {
			$vars->{$field} = $vars->{param}->{$field};
		}
		else {
			$vars->{field} = "";
		}
	}
	if (ref($vars->{categories})) {
		$vars->{categories} = join(", ", @{$vars->{categories}});
	}
	$vars->{emoticons} = $vars->{param}->{"no-emoticons"} eq "true" ? 0 : 1;
	$vars->{replies}   = $vars->{param}->{"no-replies"} eq "true" ? 0 : 1;

	# Are we publishing?
	if ($vars->{param}->{publish} eq "true") {
		# Validate their inputs.
		my $invalid = 0;
		if (length $vars->{body} == 0) {
			$invalid = 1;
			push (@{$vars->{errors}}, "You must enter a body for your blog post.");
		}

		# Make sure the times are valid.
		if ($vars->{month} =~ /[^0-9]/ || ($vars->{month} < 1 || $vars->{month} > 12)) {
			$vars->{month} = 1;
		}
		if ($vars->{day} =~ /[^0-9]/ || ($vars->{day} < 1 || $vars->{day} > 31)) {
			$vars->{day} = 1;
		}
		if ($vars->{year} =~ /[^0-9]/ || length $vars->{year} != 4) {
			$vars->{year} = 2000;
		}
		foreach (qw(hour min sec)) {
			if ($vars->{$_} =~ /[^0-9]/ || ($vars->{$_} < 0 || $vars->{$_} > 59)) {
				$vars->{$_} = 0;
			}
		}
		if ($vars->{hour} > 23) {
			$vars->{hour} = 23;
		}

		# Format the categories.
		my $tags = [];
		my @categories = split(/\,/, $vars->{categories});
		foreach my $tag (@categories) {
			$tag = Siikir::Util::trim($tag);
			push (@{$tags}, $tag);
		}

		# Okay to update?
		if ($invalid == 0) {
			# Convert the timestamp back into epoch time.
			my $epoch = Time::Local::timelocal ($vars->{sec},$vars->{min},$vars->{hour},
				$vars->{day},($vars->{month} - 1),($vars->{year} - 1900));
			my @localtime = localtime($epoch);

			# No; updating one.
			($vars->{id}, $vars->{fid}) = $self->Master->Blog->postEntry ($vars->{uid},
				id         => $vars->{id},
				time       => $epoch,
				author     => $vars->{user},
				subject    => $vars->{subject},
				avatar     => $vars->{avatar},
				categories => $tags,
				privacy    => $vars->{privacy},
				ip         => $ENV{REMOTE_ADDR},
				emoticons  => $vars->{emoticons},
				comments   => $vars->{replies},
				body       => $vars->{body},
			);
			$vars->{published} = 1;
		}
	}
	elsif ($vars->{param}->{delete} && $vars->{param}->{confirm} eq "true") {
		# Deleting.
		my $success = $self->Master->Blog->deleteEntry ($vars->{uid}, $vars->{param}->{id});
		$vars->{deleted} = $success;
		if (!defined $success) {
			return $self->showError($vars, "Failed to delete the post: $@");
		}
	}

	return $vars;
}

1;
