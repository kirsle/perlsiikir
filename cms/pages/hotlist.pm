package Siikir::Controller::hotlist;

use strict;
use Siikir::Util;

sub process {
	my ($self, $vars, $url) = @_;

	# We need the Profile plugin.
	$self->Master->loadPlugin("Hotlist");
	$self->Master->loadPlugin("Photo");
	$self->Master->loadPlugin("Profile");

	# Must be logged in.
	if (!$vars->{login}) {
		$self->Master->CGI->redirect("/account/login?return=/hotlist");
		return $vars;
	}

	my $action = scalar @{$url} ? $url->[0] : "index";
	$vars->{photopub} = $self->Master->Photo->http();
	$vars->{action} = $action;

	# Actions.
	if ($action eq "index") {
		# Show the forward hotlist.
		$vars->{hotlist} = $self->Master->Hotlist->getHotlist($vars->{uid}, "forward");
		my $reverse = $self->Master->Hotlist->getHotlist($vars->{uid}, "reverse");

		# Handle blocks
		$vars->{hotlist} = doBlocks($self,$vars->{uid},$vars->{hotlist});
		$reverse         = doBlocks($self,$vars->{uid},$reverse);

		$vars->{reverse} = scalar @{$reverse};
	}
	elsif ($action eq "reverse") {
		# Show the reverse hotlist.
		$vars->{hotlist} = $self->Master->Hotlist->getHotlist($vars->{uid}, "reverse");

		# Handle blocks
		$vars->{hotlist} = doBlocks($self,$vars->{uid},$vars->{hotlist});
	}
	if ($action eq "add") {
		my $who = $vars->{param}->{who} || '';
		$vars->{link} = $who;

		# Resolve a volatile URL.
		$who = $self->Master->User->resolveVolatile($who);
		if (!defined $who) {
			return $self->showError($vars, "Can't add this user to your hot list: $@");
		}

		# Resolve a user ID.
		my $uid = $self->Master->User->getId($who);
		if (!defined $uid) {
			return $self->showError($vars, "That user wasn't found.");
		}

		# Can't add ourselves.
		if ($uid == $vars->{uid}) {
			return $self->showError($vars, "You can't add yourself to your hot list.");
		}

		# Add to hot list.
		my $result = $self->Master->Hotlist->add($uid, $vars->{uid});
		if (!defined $result) {
			return $self->showError($vars, "Failed to add the user to your hot list: $@");
		}

		$vars->{profile} = $self->Master->Profile->getProfile($uid);
		$vars->{success} = 1;
	}
	if ($action eq "remove") {
		my $who = $vars->{param}->{who} || '';
		$vars->{link} = $who;

		# Resolve a volatile URL.
		$who = $self->Master->User->resolveVolatile($who);
		if (!defined $who) {
			return $self->showError($vars, "Can't add this user to your hot list: $@");
		}

		# Resolve a user ID.
		my $uid = $self->Master->User->getId($who);
		if (!defined $uid) {
			return $self->showError($vars, "That user wasn't found.");
		}

		# Remove from hot list.
		my $result = $self->Master->Hotlist->remove($uid, $vars->{uid});
		if (!defined $result) {
			return $self->showError($vars, "Failed to remove the user from your hot list: $@");
		}

		$vars->{profile} = $self->Master->Profile->getProfile($uid);
		$vars->{success} = 1;
	}

	return $vars;
}

sub doBlocks {
	my $self = shift;
	my $uid  = shift;
	my $list = shift;

	my $new = [];
	foreach my $user (@{$list}) {
		my $id = $user->{userid};
		if ($self->Master->User->isBlocked($uid, $id) || $self->Master->User->isBlocked($id, $uid)) {
			next;
		}
		push (@{$new}, $user);
	}

	return $new;
}

1;
