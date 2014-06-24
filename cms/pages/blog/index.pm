package Siikir::Controller::blog::index;

use strict;
use Siikir::Util;

sub process {
	my ($self, $vars, $url) = @_;

	# We need the Profile plugin.
	$self->Master->loadPlugin("Profile");
	$self->Master->loadPlugin("Photo");
	$self->Master->loadPlugin("Blog");
	$self->Master->loadPlugin("Comment");
	$vars->{photopub} = $self->Master->Photo->http();
	$vars->{avatarpub} = $self->Master->Blog->avatarHttp();

	# What user are they viewing?
	my $user = scalar @{$url} ? $url->[0] : "";
	if (length $user == 0) {
		# Assume the local user.
		if ($vars->{login}) {
			$user = $vars->{uid};
		}
		else {
			# Assume the admin user.
			$user = 1;
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

	# What page are they viewing?
	my $page = scalar @{$url} >= 2 ? $url->[1] : "";
	$page = "index" unless length $page > 0;
	$vars->{display} = $page;
	if ($page eq "categories") {
		# Just a category view.
		my $categories = $self->Master->Blog->getCategories($user);
		my @sorted = sort {
			scalar(keys(%{$categories->{$b}})) <=> scalar(keys(%{$categories->{$a}}))
		} keys %{$categories};

		# Group each category by number of posts so we can sort each group.
		my $grouped = {};
		foreach my $cat (@sorted) {
			my $count = scalar keys %{$categories->{$cat}};
			if (!exists $grouped->{$count}) {
				$grouped->{$count} = [];
			}
			push (@{$grouped->{$count}}, $cat);
		}

		$vars->{order} = [];
		foreach my $group (sort { $b <=> $a } keys %{$grouped}) {
			foreach my $cat (sort(@{$grouped->{$group}})) {
				push (@{$vars->{order}}, [ $cat, $group ]);
			}
		}
	}
	elsif ($page eq "index" || $page eq "category") {
		# The index view. Get their most recent posts.
		my $index = $self->Master->Blog->getIndex($user,$vars->{uid});

		# Category?
		my $category = undef;
		my $label    = scalar @{$url} >= 2 ? $url->[2] : "";
		if ($page eq "category") {
			# Get the category index.
			my $categories = $self->Master->Blog->getCategories($user);
			if (!exists $categories->{$label}) {
				return $self->showError($vars, "There are no posts with that category.");
			}
			$category = $categories->{$label};
		}

		# Sort the index.
		my @pool =
			# Narrow by category.
			defined $category
			?
				grep {
					grep { $_ eq $label } @{$index->{$_}->{categories}}
				} keys %{$index}
			:
				keys %{$index};
		$vars->{category} = $label;
		my @ordered = ();
		my @sticky  = grep { $index->{$_}->{sticky} } @pool;
		my @normal  = grep { !$index->{$_}->{sticky} } @pool;
		push (@ordered, sort { $index->{$b}->{time} <=> $index->{$a}->{time} } @sticky);
		push (@ordered, sort { $index->{$b}->{time} <=> $index->{$a}->{time} } @normal);

		# Posts per page.
		my $ppp = $self->Master->Blog->entriesPerPage();

		# Handle offsets.
		my $offset = $vars->{param}->{skip} || 0;
		$vars->{offset}  = $offset;
		$vars->{earlier} = $offset > 0 ? ($offset - $ppp) : 0;
		$vars->{older}   = ($offset + $ppp) < scalar(@ordered) ? $offset + $ppp : 0;
		$vars->{earlier} = 0 if $vars->{earlier} < 0;
		$vars->{older}   = 0 if $vars->{older} < 0;
		$vars->{can_older}   = $vars->{older} == 0 ? 0 : 1;
		$vars->{can_earlier} = $offset > 0 ? 1 : 0;
		$vars->{count}       = 0;

		# Get the user's default photo.
		$vars->{photo} = $self->Master->Photo->getProfilePhoto($user);

		# Load the selected posts.
		$vars->{posts} = [];
		for (my $i = $offset; $i < scalar(@ordered) && $i < ($offset + $ppp); $i++) {
			my $id = $ordered[$i];
			my $post = $self->Master->Blog->getEntry($user,$id);

			my $tz = $vars->{login} ? $vars->{account}->{profile}->{timezone} : $self->{timezone};
			$post->{pretty_time} = Siikir::Time::getLocalTimestamp (
				"Weekday, Mon dd yyyy @ H:mm AM", $post->{time}, $tz
			);

			# Get the comments for this post.
			my $comments = $self->Master->Comment->getComments($user, "blog-$id");
			$post->{comment_count} = scalar keys %{$comments};

			push (@{$vars->{posts}}, $post);

			$vars->{count}++;
		}
	}
	else {
		$vars->{display} = "entry";

		# Viewing a blog post. Did they provide an ID or a friendly ID?
		my $id = $self->Master->Blog->resolveId($user,$page,undef,$vars->{uid});
		if (!defined $id) {
			return $self->showError($vars, "The requested blog post was not found.");
		}

		# Get the post.
		$vars->{post} = $self->Master->Blog->getEntry($user,$id);

		# If no avatar, get their photo.
		if (!$vars->{post}->{avatar}) {
			$vars->{photo} = $self->Master->Photo->getProfilePhoto($user);
		}

		# Pretty-print the time.
		my $tz = $vars->{login} ? $vars->{account}->{profile}->{timezone} : $self->{timezone};
		$vars->{post}->{pretty_time} = Siikir::Time::getLocalTimestamp (
			"Weekday, Mon dd yyyy @ H:mm AM", $vars->{post}->{time}, $tz
		);
	}

	return $vars;
}

1;
