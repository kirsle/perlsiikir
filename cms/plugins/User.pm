package Siikir::Plugin::User 2012.0308;

use 5.14.0;
use strict;
use warnings;
use Digest::MD5 qw(md5_hex);

use base "Siikir::Plugin";
use Siikir::Util;

=head1 NAME

Siikir::Plugin::User - User management plugin.

=cut

sub init {
	my $self = shift;

	$self->debug("User plugin loaded!");
	$self->requires("JsonDB", "Photo", "Search");

	# Options
	$self->options (
		# How long will volatile links to profiles live for?
		volatile => 60*15, # 15 minutes
	);
	$self->interface([
		{
			category => "User Options",
			fields   => [
				{
					name  => "volatile",
					label => "Volatile Links Lifetime",
					text  => "This sets the amount of time (in seconds) that a volatile link to a profile will be good for.",
					type  => "number",
				},
			],
		},
	]);
}

=head1 METHODS

=head1 string generateSalt ()

When a new user signs up, a unique salt is generated for the user to hash their
password with. This method generates a random string to use as a salt.

=cut

sub generateSalt {
	my $self = shift;

	# The salt will be 16 random characters.
	my @letters = qw(
		A B C D E F G H I J K L M N O P Q R S T U V W X Y Z
		a b c d e f g h i j k l m n o p q r s t u v w x y z
		0 1 2 3 4 5 6 7 8 9 ` ~ ! @ $ % ^ & * - _ = + / * |
		[ ] { } . < > ?
	);
	my $salt = '';
	while (length $salt < 16) {
		$salt .= $letters [ int(rand(scalar(@letters))) ];
	}

	return $salt;
}

=head2 string salt (int userid, string password[, string salt[, bool nohash]])

Salt a user's password. This method is versatile: if provided only a user ID
and password, their profile will be looked up to get the salt. If provided the
salt, that salt will be used (useful for new user registration).

Examples:

  # When creating a new user
  my $salt = $self->generateSalt();
  my $hash = $self->salt (1000, "secret", $salt);

  # When verifying a log in
  my $hash = $self->salt (1000, "secret");
  if ($hash eq $account->{password}) {
    # valid login
  }

The password hashing algorithm is:

  md5( user_id + salt + md5(password) )

If the C<nohash> option is provided, the password given to this function is
assumed to already be a flat MD5 hash of the password. You can feel free to
provide C<undef> as the C<salt> parameter if you need to provide C<nohash>.

=cut

sub salt {
	my ($self,$uid,$password,$salt,$nohash) = @_;
	$uid = Siikir::Util::stripID($uid);

	# If not provided a salt, the UID must be valid.
	if (!defined $salt || !length $salt) {
		if (!$self->userExists(id => $uid)) {
			$@ = "No salt provided and user ID $uid doesn't exist.";
			return undef;
		}
		my $db = $self->getAccount($uid);
		$salt = $db->{salt};
	}

	# Make sure we're hashing the byte stream for Unicode passwords.
	$password = Siikir::Util::utf8_encode($password);

	# Hash the password.
	$password = md5_hex($password) unless $nohash;

	# Return the final hashed string.
	return md5_hex ( $uid . $salt . $password );
}

=head2 bool isAdmin (int uid)

Check if the given user ID is an admin user.

=cut

sub isAdmin {
	my ($self,$id) = @_;
	$id = Siikir::Util::stripID($id);

	my $acct = $self->getAccount($id);
	if (defined $acct->{level} && $acct->{level} eq "admin") {
		return 1;
	}

	return 0;
}

=head2 bool userExists ("id" | "name" => value)

Query whether a user exists by ID or name.

=cut

sub userExists {
	my ($self,$by,$value) = @_;
	$value = Siikir::Util::stripUsername($value);
	return undef unless defined $value;

	# Exists?
	if ($by eq "id") {
		return undef if $value == 0; # The guest user NEVER exists
		return $self->Master->JsonDB->documentExists("users/by-id/$value");
	}
	else {
		return $self->Master->JsonDB->documentExists("users/by-name/$value");
	}
}

=head2 aref listUsers ()

Return a list of all user IDs that exist on the server.

=cut

sub listUsers {
	my $self = shift;

	my @users = $self->Master->JsonDB->listDocuments("users/by-id");
	return [ sort { $a <=> $b } @users ];
}

=head2 bool addUser (hash options)

Create a new user. Returns the user ID on success or undef on error (and
it will set C<$@> on error too).

Options include:

  username -Required
  password -Required, clear text password
  id       -Optional, default = next ID starting at 1,000
  level    -Optional, default = user, could be admin
  dob      -Required, yyyy-mm-dd format, user's birthday
  any arbitrary profile fields

=cut

sub addUser {
	my ($self,%opts) = @_;

	# Get the user account options first.
	my $username = delete $opts{username} || "";
	my $id       = delete $opts{id} || "";
	my $password = delete $opts{password} || "";
	my $level    = delete $opts{level} || "user";
	my $dob      = delete $opts{dob} || "";

	# Default the level.
	$level = "user" unless $level eq "admin";

	# Everything else is profile values.
	my $profile = { %opts };

	# Check the user name.
	$username = Siikir::Util::stripUsername($username);
	$id       = Siikir::Util::stripID($id);
	if (length $username == 0) {
		$@ = "You must provide a username.";
		return undef;
	}
	elsif ($self->userExists(name => $username)) {
		$@ = "That username already exists.";
		return undef;
	}
	elsif (!$self->validUsername($username)) {
		$@ = "That username isn't valid: $@";
		return undef;
	}

	# Did they pass an ID? Did it exist?
	if (defined $id && length $id > 0) {
		if ($self->userExists(id => $id)) {
			$@ = "User ID $id already registered!";
			return undef;
		}
	}
	else {
		# Get the next free ID.
		$id = $self->nextId();
	}

	# Generate a new salt for this user.
	my $salt = $self->generateSalt();

	# Salt their hash.
	my $hash = length $password ? $self->salt($id, $password, $salt) : "";

	# Create the user's account.
	$self->Master->JsonDB->writeDocument("users/by-id/$id", {
		account => {
			id       => $id,
			level    => $level,
			username => $username,
			password => $hash,
			salt     => $salt,
			dob      => $dob,
			blocked  => [],
		},
	});

	# Map the username to the ID.
	$self->Master->JsonDB->writeDocument("users/by-name/$username", {
		id => $id,
	});

	# All good!
	return $id;
}

=head2 bool removeUser (int id)

Remove a user account. This will perform the following actions:

  * The user's account file gets "level => deleted" in /users/by-id/
  * The user loses their username in /users/by-id/
  * The user's "by-name" and "by-facebook" are deleted.
  * The user's profile is deleted.
  * deletePhoto is called for all of the user's photos. Their photo album DB
    is then also deleted.
  * The search cache is rebuilt.

Messages, comments, hot list entries, etc. are left alone.

=cut

sub removeUser {
	my ($self,$id) = @_;
	$id = Siikir::Util::stripID($id);

	# User must exist.
	if (!$self->userExists(id => $id)) {
		$@ = "User ID $id wasn't found.";
		return undef;
	}

	$self->debug("### DELETING USER ID: $id ###");

	# Delete all their photos.
	my $albums = $self->Master->Photo->getAlbums($id, $id);
	foreach my $album (@{$albums}) {
		my $name = $album->{name};
		$self->debug("Delete their photo album: $name");
		my $photos = $self->Master->Photo->getAlbum($id, $name, $id);
		foreach my $photo (@{$photos}) {
			# Delete it.
			$self->debug("Deleting photo key: $photo->{key}");
			$self->Master->Photo->deletePhoto($id, $photo->{key});
		}
	}

	# Mark them deleted.
	my $acct     = $self->getAccount($id);
	my $username = $acct->{username};
	my $facebook = $acct->{facebook};
	$acct->{username} = "";
	$acct->{facebook} = "";
	$acct->{level}    = "deleted";
	$self->setAccount($id, $acct);

	# Delete the username and facebook.
	$self->Master->JsonDB->deleteDocument("users/by-name/$username");
	$self->Master->JsonDB->deleteDocument("users/by-facebook/$facebook") if length $facebook;

	# Delete the profile.
	$self->Master->JsonDB->deleteDocument("profile/$id");

	# Delete the photo album.
	$self->Master->JsonDB->deleteDocument("photos/$id");

	# Rebuild the search cache.
	$self->Master->Search->buildCache();

	# All done!
	return 1;
}

=head2 bool changeUsername (int id, string newuser)

Change a user's username. C<id> is the user ID and C<newuser> is the new
username.

=cut

sub changeUsername {
	my ($self,$id,$username) = @_;
	$id       = Siikir::Util::stripID($id);
	$username = Siikir::Util::stripUsername($username);

	if (!$self->userExists(id => $id)) {
		$@ = "User ID $id wasn't found.";
		return undef;
	}
	if (!$self->validUsername($username)) {
		$@ = "Invalid username: $@";
		return undef;
	}
	if ($self->userExists(name => $username)) {
		$@ = "That username is already in use.";
		return undef;
	}

	# Load their account by ID.
	my $acct = $self->getAccount($id);

	# Update their username.
	my $old = Siikir::Util::stripUsername($acct->{username});
	$acct->{username} = $username;

	# Unlink their old by-name.
	$self->Master->JsonDB->deleteDocument("users/by-name/$old");

	# Save their new docs.
	$self->setAccount($id, $acct);
	$self->Master->JsonDB->writeDocument("users/by-name/$username", {
		id => $id,
	});

	return 1;
}

=head2 bool changePassword (int uid, string password)

Change a user's password. This will also generate a new salt for the user.

=cut

sub changePassword {
	my ($self,$uid,$password) = @_;
	$uid = Siikir::Util::stripID($uid);

	if (!$self->userExists(id => $uid)) {
		$@ = "User ID $uid not found.";
		return undef;
	}

	# Load their account.
	my $acct = $self->getAccount($uid);

	# Generate a new salt for this user.
	my $salt = $self->generateSalt();

	# Salt their password.
	my $hash = $self->salt($uid, $password, $salt);

	# Update their account.
	$acct->{password} = $hash;
	$acct->{salt}     = $salt;
	$self->setAccount($uid, $acct);

	return 1;
}

=head2 bool validUsername (string username)

Test if a given username is valid. Valid usernames are:

  * Can't begin with a number
  * Less than 30 characters long

If invalid, C<$@> will contain the reason why.

=cut

sub validUsername {
	my ($self,$username) = @_;
	my $strip = Siikir::Util::stripUsername($username);

	if (length $username == 0) {
		$@ = "Username can't be empty!";
		return undef;
	}
	elsif ($username ne $strip) {
		$@ = "Username contains illegal characters!";
		return undef;
	}
	elsif (length $username > 30) {
		$@ = "Username can't be longer than 30 characters.";
		return undef;
	}
	elsif ($username =~ /^\d+/) {
		$@ = "Usernames can't begin with a number.";
		return undef;
	}

	return 1;
}

=head2 hash getAccount (int id)

Get the user ID's account info (username, etc.)

=cut

sub getAccount {
	my ($self,$id) = @_;
	$id = Siikir::Util::stripID($id);

	if ($self->userExists(id => $id)) {
		my $data = $self->Master->JsonDB->getDocument("users/by-id/$id");
		return $data->{account};
	}

	return undef;
}

=head2 bool setAccount (int id, href account)

Overwrite the user's account details with the given hashref. This should only
be done after doing C<getAccount> and making modifications.

=cut

sub setAccount {
	my ($self,$id,$acct) = @_;
	$id = Siikir::Util::stripID($id);

	# The account should NOT contain the profile. It's a bug if it does.
	delete $acct->{profile};

	if ($self->userExists(id => $id)) {
		$self->Master->JsonDB->writeDocument("users/by-id/$id", { account => $acct });
		return 1;
	}

	return undef;
}

=head2 int getIdByName (string username)

Get a username's ID, or undef if not found.

=cut

sub getIdByName {
	my ($self,$username) = @_;
	$username = Siikir::Util::stripUsername($username);

	if (!$self->userExists(name => $username)) {
		return undef;
	}

	my $data = $self->Master->JsonDB->getDocument("users/by-name/$username");
	return $data->{id};
}

=head2 string getUsername (string username || int uid)

Given data that could be either a username or an ID, get the username.

=cut

sub getUsername {
	my ($self,$unknown) = @_;
	$unknown = Siikir::Util::stripUsername($unknown);

	#  Does it look like an ID?
	if ($unknown =~ /^\d+$/) {
		if (!$self->userExists(id => $unknown)) {
			$@ = "User ID $unknown not found!";
			return undef;
		}

		my $user = $self->getAccount($unknown);
		return $user->{username};
	}
	else {
		if ($self->userExists(name => $unknown)) {
			return $unknown;
		}
		else {
			$@ = "User name $unknown not found!";
			return undef;
		}
	}
}

=head2 int getId (string username || int uid)

Given data that could be either a username or an ID, get the ID.

=cut

sub getId {
	my ($self,$unknown) = @_;
	$unknown = Siikir::Util::stripUsername($unknown);

	# Does it look like an ID?
	if (defined $unknown && $unknown =~ /^\d+$/) {
		if (!$self->userExists(id => $unknown)) {
			$@ = "User ID $unknown not found!";
			return undef;
		}
		return $unknown;
	}

	return $self->getIdByName($unknown);
}

=head2 bool blockUser (int uid, int to-block)

Add C<to-block> to the block list for user C<uid>.

=cut

sub blockUser {
	my ($self,$uid,$block) = @_;
	$uid = Siikir::Util::stripID($uid);
	$block = Siikir::Util::stripID($block);

	# Exists?
	if (!$self->userExists(id => $uid)) {
		$@ = "Blocklist owner user ID $uid not found!";
		return undef;
	}
	elsif (!$self->userExists(id => $block)) {
		$@ = "Blocklist target user ID $block not found!";
		return undef;
	}

	my $acct = $self->getAccount($uid);
	if (!exists $acct->{blocked}) {
		$acct->{blocked} = [];
	}

	# Don't block twice.
	foreach my $user (@{$acct->{blocked}}) {
		if ($user == $block) {
			return 1;
		}
	}

	unshift (@{$acct->{blocked}}, $block);
	$self->setAccount($uid, $acct);
	return 1;
}

=head2 bool unblockUser (int uid, int to-unblock)

Remove a user from your block list.

=cut

sub unblockUser {
	my ($self,$uid,$block) = @_;
	$uid = Siikir::Util::stripID($uid);
	$block = Siikir::Util::stripID($block);

	# Exists?
	if (!$self->userExists(id => $uid)) {
		$@ = "Blocklist owner user ID $uid not found!";
		return undef;
	}
	elsif (!$self->userExists(id => $block)) {
		$@ = "Blocklist target user ID $block not found!";
		return undef;
	}

	my $acct = $self->getAccount($uid);
	if (!exists $acct->{blocked}) {
		$acct->{blocked} = [];
	}

	# Unblock them.
	my $new = [];
	foreach my $user (@{$acct->{blocked}}) {
		if ($user == $block) {
			next;
		}
		push (@{$new}, $user);
	}

	$acct->{blocked} = $new;
	$self->setAccount($uid, $acct);
	return 1;
}

=head2 bool isBlocked (int uid, int target)

Test whether the user C<uid> has listed C<target> on their blocked list.

=cut

sub isBlocked {
	my ($self,$uid,$target) = @_;
	$uid = Siikir::Util::stripID($uid);
	$target = Siikir::Util::stripID($target);

	return undef unless defined $uid;
	return undef unless defined $target;

	# Exists?
	if (!$self->userExists(id => $uid)) {
		$@ = "Blocklist owner user ID $uid not found!";
		return undef;
	}
	elsif (!$self->userExists(id => $target)) {
		$@ = "Blocklist target user ID $target not found!";
		return undef;
	}

	# Admins are unblockable and can't block; they need full visibility.
	if ($self->isAdmin($uid) || $self->isAdmin($target)) {
		return 0;
	}

	my $acct = $self->getAccount($uid);
	if (!exists $acct->{blocked}) {
		$acct->{blocked} = [];
	}

	# Are they blocked?
	foreach my $user (@{$acct->{blocked}}) {
		if ($user == $target) {
			return 1;
		}
	}

	return 0;
}

=head2 bool isOnline (int userid)

See if the user is currently online or now (Session manages this).

=cut

sub isOnline {
	my ($self,$uid) = @_;
	$uid = Siikir::Util::stripID($uid);

	# User not found?
	if (!$self->userExists(id => $uid)) {
		$@ = "User ID $uid not found.";
		return undef;
	}

	# Online?
	if ($self->Master->JsonDB->documentExists("online/$uid")) {
		return 1;
	}

	return undef;
}

=head2 int lastSeen (int userid, [time_t time])

Dual-use method. If called with no arguments, returns the number of seconds ago
that the user was last seen online. If you pass an argument (a value of C<time>),
their last seen time is set in their account (Session calls this on all commits
while a user is logged in).

=cut

sub lastSeen {
	my ($self,$uid,$time) = @_;
	$uid = Siikir::Util::stripID($uid);

	# Exists?
	if (!$self->Master->User->userExists(id => $uid)) {
		return undef;
	}

	# Get their account.
	my $acct = $self->getAccount($uid);

	# Time?
	if (defined $time && $time =~ /^\d+$/) {
		# Update their account.
		$acct->{lastseen} = $time;
		$self->setAccount($uid, $acct);
		return 0;
	}

	# Return their last seen time.
	if (exists $acct->{lastseen} && length $acct->{lastseen}) {
		return time() - $acct->{lastseen};
	}

	return undef;
}

=head2 int login (string username, string password)

Validate a username and password combination. If the login details are correct,
the ID of the user they're for will be returned. If not, undef is returned.

=cut

sub login {
	my ($self,$username,$password) = @_;
	$username = Siikir::Util::stripUsername($username);

	# Get the user's ID.
	if (!$self->userExists(name => $username)) {
		$@ = "User name $username was not found.";
		return undef;
	}
	my $id = $self->getIdByName($username);

	# Get their account.
	my $acct = $self->getAccount($id);

	# Test the passwords.
	my $hash = $self->salt($id, $password);
	if ($hash eq $acct->{password}) {
		# Wonderful!
		return $id;
	}

	$@ = "Incorrect username or password.";
	return undef;
}

=head2 bool become (int id)

Log in the end user as the user with ID C<id>. This will no-messing-around log
in the end user as this ID no matter what. This is done i.e. when the user first
signs up. Handle with care. User login(user,pass) if you want authentication.

=cut

sub become {
	my ($self,$id) = @_;
	$id = Siikir::Util::stripID($id);

	# User exists?
	if (!$self->userExists(id => $id)) {
		return undef;
	}

	# Log them in!
	$self->Master->Session->set (
		login => 1,
		uid   => $id,
	);
}

=head2 void forget ()

Logs the user out and turns them back into a guest.

=cut

sub forget {
	my $self = shift;

	# Get their UID first.
	my $uid = $self->Master->Session->get("uid");
	$uid = Siikir::Util::stripID($uid); # Session fields are tainted.

	# Log them out!
	$self->Master->Session->set (
		login => 0,
		uid   => 0,
	);

	# Delete their "online now" status.
	if (defined $uid && $uid =~ /^\d+$/ && $uid > 0) {
		$self->Master->JsonDB->deleteDocument("online/$uid");
	}
}

=head2 int nextId ()

Gets the next free user ID for a new user, beginning with ID 1000.

=cut

sub nextId {
	my $self = shift;

	my $i = 1000;
	while ($self->userExists(id => $i)) {
		$i++;
	}

	return $i;
}

=head2 string generateVolatile (int userid, bool shareable, hash options)

For user privacy, search result links to profiles should use a temporary volatile
hash in place of the real user name, so that a permanent link to the profile can't
be bookmarked in a web browser. This method is used to generate a volatile link.

C<userid> is the user ID that you want a link for (e.g. the user whose profile is
going to be viewed). C<shareable> is whether the link can be shared with other users
or not, via other channels (e.g. Instant Messenger).

By default the volatile link is bound to the user session of the user who generated
the link and can't be shared.

Returns the unique URL component for the volatile link. It will look like:

  ~ABCDEF0

Where the letters are 8 random hexadecimal characters.

C<options> can be an arbitrary key/value store for any special privileges the
volatile link includes (like the ability to view private photos). The option
C<expires> may override the number of seconds a volatile link is good for.

=cut

sub generateVolatile {
	my ($self,$uid,$shareable,%options) = @_;
	$uid = Siikir::Util::stripID($uid);

	# Get the end user's session ID.
	my $sessid = $self->Master->Session->get("sessid");
	if (!defined $sessid || !length $sessid) {
		die "No valid session ID was found!";
		return undef;
	}

	# Generate a unique volatile name.
	my $uniq = Siikir::Util::randomHash(8);
	while ($self->Master->JsonDB->documentExists("volatile/$uniq")) {
		$uniq = Siikir::Util::randomHash(8);
	}

	# Custom expiration date?
	my $expires = $self->{volatile};
	if (exists $options{expires} && $options{expires} =~ /^\d+$/) {
		$expires = delete $options{expires};
	}

	# Populate the volatile DB.
	my $db = {
		key     => $uniq,
		created => time(),
		expires => time() + $expires,
		creator => $sessid,
		uid     => $uid,
		share   => $shareable ? 1 : 0,
		options => { %options },
	};

	$self->Master->JsonDB->writeDocument("volatile/$uniq", $db);
	return '~' . $uniq;
}

=head2 string getVolatile (string key)

Look up the stored volatile data by the given key. If the key exists but
has expired, it will be deleted and undef will be returned. If the key
doesn't exist, undef is returned. You can check C<$@> for details about
why undef is returned.

Returns the hash of fields from the volatile file. Keys will include:

  key
  created
  expires
  creator
  uid
  share

=cut

sub getVolatile {
	my ($self,$key) = @_;
	$key = Siikir::Util::stripPaths($key);

	if (!$self->Master->JsonDB->documentExists("volatile/$key")) {
		$@ = "Volatile key $key not found.";
		return undef;
	}

	# Read.
	my $db = $self->Master->JsonDB->getDocument("volatile/$key");

	# Expired?
	if (time() > $db->{expires}) {
		# Delete it.
		$self->Master->JsonDB->deleteDocument("volatile/$key");
		$@ = "Volatile key $key has expired.";
		return undef;
	}

	# Return it.
	return $db;
}

=head2 string resolveVolatile (string link[, bool forcelink])

A handy shortcut function for all the pages to use. Given an item that may be
a user ID, user name or a volatile link, this method will resolve who it refers
to and return the user.

If the given C<link> looks like a volatile link (e.g. it begins with a tilde)
the volatile entry will be looked up. If the user has permission to use this
link (e.g. they created it, or it's shareable) the user ID (int) will be returned.
Otherwise, undef will be returned.

If the given C<link> instead looks like a user ID or user name, that will be
returned.

In short: this method will only return undef if you give it a volatile link
and the volatile data is expired or the user is not allowed to use the link.
Otherwise, it will return the user ID the volatile link refers to, or else
it will return the data you gave it.

If the link provided is a regular username (not a volatile URL), but the
user requests that their profile be unlinkable, this will also return undef.

If forcelink is provided, users with "unlinkable" will still be returned.

=cut

sub resolveVolatile {
	my ($self,$link,$forcelink) = @_;

	# Does it look volatile?
	if ($link =~ /^\~([A-Za-z0-9]+?)$/) {
		my $key = $1;

		# Look it up.
		my $db = $self->getVolatile($key);
		if (!defined $db) {
			$@ = "This volatile link has expired and can no longer be used. $@";
			return undef;
		}

		# Is the user allowed to view it?
		if ($db->{share}) {
			# Yes, it's shareable.
			return $db->{uid};
		}

		# It's not share-able. Make sure our sessid matches.
		my $sessid = $self->Master->Session->get("sessid");
		if ($sessid eq $db->{creator}) {
			return $db->{uid};
		}

		$@ = "This volatile link is not share-able; you can't use it.";
		return undef;
	}

	# If forcelink, return it even if the user is unlinkable.
	return $link if $forcelink;

	# Resolve a user ID. If the user doesn't want permanent links,
	# then don't allow a permanent link.
	my $id = $self->getId($link);
	if (defined $id) {
		my $profile = $self->Master->Profile->getProfile($id);
		if (defined $profile->{privacy} && $profile->{privacy} =~ /unlinkable/) {
			# The user doesn't wanna be linked to. Unless we're the admin...
			my $me = $self->Master->Session->get("uid");
			if (!$self->isAdmin($me) && $profile->{userid} != $me) {
				$@ = "This user's profile can't be linked to directly.";
				return undef;
			}
		}
	}

	# No, just return it.
	return $link;
}

=head2 void expireVolatile ()

Loop through all the volatile documents and auto-expire old ones.

=cut

sub expireVolatile {
	my $self = shift;

	my @docs = $self->Master->JsonDB->listDocuments("volatile");
	foreach my $key (@docs) {
		my $doc = $self->getVolatile($key);
		if (time() > $doc->{expires}) {
			$self->Master->JsonDB->deleteDocument("volatile/$key");
		}
	}
}

1;
