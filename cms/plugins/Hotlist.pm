package Siikir::Plugin::Hotlist 2011.0930;

use 5.14.0;
use strict;
use warnings;
use Image::Magick;
use LWP::Simple;
use Digest::MD5 qw(md5_hex);
use File::Copy;

use base "Siikir::Plugin";

=head1 NAME

Siikir::Plugin::Hotlist - A bookmark system that notifies users they've
been bookmarked!

=cut

sub init {
	my $self = shift;

	$self->debug("Hotlist plugin loaded!");
	$self->requires(qw(User Profile Photo JsonDB));
}

=head1 METHODS

=head2 bool add (int userid, int context)

Add a user C<userid> to the hot list of C<context>. Sends an e-mail to C<userid>
to notify them of their hotness. Updates both users' hot lists (forward and
reverse, respectively).

=cut

sub add {
	my ($self,$uid,$context) = @_;
	$uid     = Siikir::Util::stripID($uid);
	$context = Siikir::Util::stripID($context);

	# Both must exist.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "User ID $uid not found.";
		return undef;
	}
	if (!$self->Master->User->userExists(id => $context)) {
		$@ = "User ID $uid not found.";
		return undef;
	}

	# Get their hot lists.
	my $me   = $self->getHotlists($context);
	my $them = $self->getHotlists($uid);

	# Don't allow duplicate addings.
	foreach my $user (@{$me->{forward}}) {
		if ($user == $uid) {
			$@ = "This user has already been added to your hot list.";
			return undef;
		}
	}

	# Add each other.
	unshift (@{$me->{forward}},   $uid);
	unshift (@{$them->{reverse}}, $context);

	# E-mail the user.
	my $profile = $self->Master->Profile->getProfile($uid);
	my $admirer = $self->Master->Profile->getProfile($context);
	$self->Master->Messaging->sendMessage (
		from    => $context,
		to      => $uid,
		subject => "You're Hot!",
		message => "Hello $profile->{displayname}!\n\n"
			. "$admirer->{displayname} thinks you're hot! You've been added to their hot list!\n\n"
			. "To view their profile, go to: http://www.siikir.com/users/$admirer->{username}\n"
			. "To view who thinks you're hot, go to: http://www.siikir.com/hotlist/reverse\n\n"
			. "Note: this is an automated message. Do not reply to this e-mail.",
	);

	# Save the hot lists.
	$self->saveHotlists($uid, $them);
	$self->saveHotlists($context, $me);

	return 1;
}

=head2 bool remove (int userid, int context)

Remove C<userid> from the hot list of C<context>.

=cut

sub remove {
	my ($self,$uid,$context) = @_;
	$uid     = Siikir::Util::stripID($uid);
	$context = Siikir::Util::stripID($context);

	# Both must exist.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "User ID $uid not found.";
		return undef;
	}
	if (!$self->Master->User->userExists(id => $context)) {
		$@ = "User ID $uid not found.";
		return undef;
	}

	# Get their hot lists.
	my $me   = $self->getHotlists($context);
	my $them = $self->getHotlists($uid);

	# Search and remove.
	my $newMe = [];
	my $newThem = [];
	foreach my $user (@{$me->{forward}}) {
		next if $user == $uid;
		push (@{$newMe}, $user);
	}
	foreach my $user (@{$them->{reverse}}) {
		next if $user == $context;
		push (@{$newThem}, $user);
	}

	# Save them.
	$me->{forward} = $newMe;
	$them->{reverse} = $newThem;
	$self->saveHotlists($uid, $them);
	$self->saveHotlists($context, $me);

	return 1;
}

=head2 bool saveHotlists (int userid, href lists)

Save the user's hot lists. C<lists> is a hashref containing C<forward> and
C<reverse>, which are arrays of user IDs.

=cut

sub saveHotlists {
	my ($self,$uid,$lists) = @_;
	$uid = Siikir::Util::stripID($uid);

	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "User ID $uid not found.";
		return undef;
	}

	my $forward = $lists->{forward} || [];
	my $reverse = $lists->{reverse} || [];

	$self->Master->JsonDB->writeDocument("hotlist/forward/$uid", $forward);
	$self->Master->JsonDB->writeDocument("hotlist/reverse/$uid", $reverse);

	return 1;
}

=head2 href getHotlists (int userid)

Retrieve the forward and reverse hot lists for C<userid>.

=cut

sub getHotlists {
	my ($self,$uid) = @_;
	$uid = Siikir::Util::stripID($uid);

	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "User ID $uid not found.";
		return undef;
	}

	my $return = {
		forward => [],
		reverse => [],
	};

	if ($self->Master->JsonDB->documentExists("hotlist/forward/$uid")) {
		$return->{forward} = $self->Master->JsonDB->getDocument("hotlist/forward/$uid");
	}
	if ($self->Master->JsonDB->documentExists("hotlist/reverse/$uid")) {
		$return->{reverse} = $self->Master->JsonDB->getDocument("hotlist/reverse/$uid");
	}

	return $return;
}

=head2 aref getHotlist (int userid, string list)

Retrieve a detailed hot list for the user. C<list> should be a string saying either
"forward" or "reverse".

=cut

sub getHotlist {
	my ($self,$uid,$list) = @_;
	$uid = Siikir::Util::stripID($uid);

	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "User ID $uid not found.";
		return undef;
	}

	my $return = [];
	my $lists  = $self->getHotlists($uid);
	if (!exists $lists->{$list}) {
		$@ = "Hot list '$list' not found for user $uid.";
		return undef;
	}

	foreach my $user (@{$lists->{$list}}) {
		my $profile = $self->Master->Profile->getProfile($user);
		next unless defined $profile; # Skip deleted users
		my $photo   = $self->Master->Photo->getProfilePhoto($user);
		$profile->{link}  = $profile->{username};
		$profile->{photo} = $photo;

		# Does this user wish to be unlinkable?
		if (defined $profile->{privacy} && $profile->{privacy} =~ /unlinkable/) {
			$profile->{link} = $self->Master->User->generateVolatile($user, $uid);
		}

		push (@{$return}, $profile);
	}

	return $return;
}

=head2 bool onHotlist (int userid, string list, int context)

See if C<userid> is on C<context>'s hot list.

=cut

sub onHotlist {
	my ($self,$uid,$list,$context) = @_;
	$uid     = Siikir::Util::stripID($uid);
	$context = Siikir::Util::stripID($context);

	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "User ID $uid not found.";
		return undef;
	}
	if (!$self->Master->User->userExists(id => $context)) {
		$@ = "User ID $context not found.";
		return undef;
	}

	my $lists = $self->getHotlists($context);
	if (!exists $lists->{$list}) {
		$@ = "Hot list '$list' not found.";
		return undef;
	}

	foreach my $user (@{$lists->{$list}}) {
		if ($user == $uid) {
			return 1;
		}
	}

	return 0;
}

1;
