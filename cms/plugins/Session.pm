package Siikir::Plugin::Session 2012.0308;

use 5.14.0;
use strict;
use warnings;
use Digest::MD5 qw(md5_hex);
use Siikir::Util;

use base "Siikir::Plugin";

=head1 NAME

Siikir::Plugin::Session - Session handling methods. Also handles keeping track
of currently online, logged-in users.

=cut

sub init {
	my $self = shift;

	$self->debug("Session plugin loaded!");

	# Required plugins.
	$self->requires(qw(
		CGI
		User
		JsonDB
	));

	# Default options.
	$self->options (
		# Name of the cookie to use for sessions.
		cookie => "SIIKIRSES",

		# How long are cookies good for?
		expires  => "+14d",        # 2 weeks (for HTTP cookie)
		lifetime => (60*60*24*14), # 2 weeks (for server cookie)

		# How recently must users have been active for them to be marked online?
		activity => 60*15,         # 15 minutes
	);
	$self->interface([
		{
			category => "Session Options",
			fields   => [
				{ section => "Cookie Settings" },
				{
					name   => "cookie",
					label  => "Cookie Name",
					text   => "The name of the HTTP browser cookie used to store the user's session ID.",
					type   => "text",
				},
				{
					name   => "expires",
					label  => "HTTP Cookie Expiration Date",
					text   => "The expiration date for the cookie (in HTTP cookie format, i.e. \"+14d\" for 2 weeks).",
					type   => "text",
				},
				{
					name   => "lifetime",
					label  => "Server Cookie Expiration Date",
					text   => "The expiration date for the server-side session (in seconds, i.e. 2 weeks = 60*60*24*14 = 1209600).",
					type   => "number",
				},

				{ section => "Online Status Settings" },
				{
					name   => "activity",
					label  => "User Activity Threshhold",
					text   => "After a user has been idle for this many seconds, they stop showing up as 'Online now!'",
					type   => "number",
				},
			],
		},
	]);

	# Expire old sessions.
	$self->expirate();

	# Does the user have a session cookie?
	my $sessid = $self->Master->CGI->getCookie($self->{cookie});
	$sessid = Siikir::Util::stripHex($sessid);
	if (!defined $sessid) {
		# They have no sessid. Initialize a new unnamed session.
		$self->debug("Making new sessid!");
		$sessid = $self->newSession();
	}
	else {
		# Get their session ID from the DB.
		if (!$self->Master->JsonDB->documentExists("session/$sessid")) {
			# Their session has expired, set them a new one.
			$self->debug("Their session expired - session/$sessid not found!");
			$sessid = $self->newSession();
		}
		else {
			$self->debug("Resuming their old session from session/$sessid");
			$self->{session} = $self->Master->JsonDB->getDocument("session/$sessid");
		}
	}

	# Keep their ID around.
	$self->{sessid} = $sessid;
}

=head1 METHODS

=head2 bool switch (string sessid)

Switch the end user's session ID to a different session. Useful in the API.

=cut

sub switch {
	my ($self,$sessid) = @_;
	$sessid = Siikir::Util::stripPaths($sessid);

	# Get their session ID from the DB.
	if ($self->Master->JsonDB->documentExists("session/$sessid")) {
		$self->debug("Switching user's session to session/$sessid");
		$self->{session} = $self->Master->JsonDB->getDocument("session/$sessid");
		$self->{sessid}  = $self->{session}->{sessid};
	}
}

=head2 void commit ()

Save all changes to the session to disk. Should be done at the end of the Page plugin.

=cut

sub commit {
	my $self = shift;

	# Save their session to disk, only if modified.
	if ($self->{session}->{modified}) {
		# Do they have a session ID yet?
		if (length $self->{sessid} == 0) {
			# No, assign one now.
			$self->{sessid} = $self->assign();
		}

		# Validate the session.
		$self->{sessid} = Siikir::Util::stripHex($self->{sessid});

		# If the user's logged in, ping their "online now" file.
		if ($self->{session}->{login}) {
			my $uid = Siikir::Util::stripUsername($self->{session}->{uid});

			# Sanity check.
			if ($self->Master->User->userExists(id => $uid)) {
				$self->Master->User->lastSeen($uid, time());
				$self->Master->JsonDB->writeDocument("online/$uid", {
					time    => time(),
					expires => time() + $self->{activity},
				});
			}
		}

		# Save the session to disk.
		$self->Master->JsonDB->writeDocument("session/$self->{sessid}", $self->{session});
	}
}

=head2 void set (hash options)

Set one or more key/value pairs in the user's session.

=cut

sub set {
	my ($self,%data) = @_;

	foreach my $key (keys %data) {
		next if $key eq "sessid";
		$self->{session}->{$key} = $data{$key};
	}

	# Their session has been modified.
	$self->{session}->{modified} = time();
}

=head2 string get (string key)

Get a key from the user's session, or undef if it doesn't exist.

=cut

sub get {
	my ($self,$key) = @_;

	return undef unless exists $self->{session}->{$key};
	return $self->{session}->{$key};
}

=head2 void expirate ()

Expire old sessions.

=cut

sub expirate {
	my $self = shift;

	# Get a session list.
	my @sessions = $self->Master->JsonDB->listDocuments("session");
	foreach my $doc (@sessions) {
		my $mtime = (stat("$self->{root}/db/session/$doc.json"))[9];
		if (time() - $mtime > $self->{lifetime}) {
			# Expire it.
			$self->Master->JsonDB->deleteDocument("session/$doc");
		}
	}

	# Get the online users list.
	my @online = $self->Master->JsonDB->listDocuments("online");
	foreach my $doc (@online) {
		my $mtime = (stat("$self->{root}/db/online/$doc.json"))[9];
		if (time() - $mtime > $self->{activity}) {
			# Expire it.
			$self->Master->JsonDB->deleteDocument("online/$doc");
		}
	}
}

=head2 string newSession ()

Initialize a new session for the end user. This is for newcomers to the site.
This will initialize the default session fields, but B<will not> assign a
session ID to the user. A Session ID is not assigned until the session has been
modified in some way from the defaults.

This returns the empty string.

=cut

sub newSession {
	my $self = shift;

	# Good, we have one! Set the default session data.
	my $session = {
		sessid   => "", # Not determined until it's modified
		modified => 0,  # last modified time of the session
		login    => 0,  # 0 = user not logged in
		uid      => 0,  # Logged-in user ID (guest is 0)
	};
	#$self->Master->JsonDB->writeDocument("session/$id", $session);

	# Keep their session here too so we have it.
	$self->{session} = $session;

	return "";
}

=head2 string assign ()

Assign a unique session ID for the user's session. This is called the first time
the user's session changes from the defaults, and a session ID must be assigned.

Returns the new session ID.

=cut

sub assign {
	my $self = shift;

	# Random number range.
	my $rand = 999_999_999;

	# Make up a random ID.
	my $id = md5_hex(int(rand($rand)));

	# Is it taken?
	while ($self->Master->JsonDB->documentExists("session/$id")) {
		$id = md5_hex(int(rand($rand)));
	}

	# Store this in their session.
	$self->{session}->{sessid} = $id;

	# Set their cookie.
	$self->Master->CGI->setCookie (
		-name    => $self->{cookie},
		-value   => $id,
		-expires => $self->{expires},
	);

	# Return the new ID.
	return $id;
}

1;
