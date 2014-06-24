package Siikir::Plugin::Photo 2011.1106;

use 5.14.0;
use strict;
use warnings;
use Image::Magick;
use LWP::UserAgent;
use Digest::MD5 qw(md5_hex);
use File::Copy;

use base "Siikir::Plugin";

=head1 NAME

Siikir::Plugin::Photo - Photo album management.

=cut

sub init {
	my $self = shift;

	$self->debug("Photo plugin loaded!");
	$self->requires(qw(Search Messaging JsonDB));

	# Options.
	$self->options(
		# Root directory via HTTP (relative to index.cgi) where photos are stored.
		# DON'T start this with ./ or the mod_rewrite acts up!
		public => "./static/photos",
		http   => "/static/photos",

		# Photo sizes.
		large  => 800,
		medium => 640,
		small  => 250,
		tiny   => 150,
		avatar => 96,
		mini   => 64,

		# Maximum number of photos a user can have.
		maximum => 12,

		# LWP User Agent.
		agent => "Mozilla/4.0 (compatible; Photo Upload Fetcher)",

		# Maximum file size for an upload.
		filesize => 1024*1024*6, # 6 MB

		# Whether adult photos are allowed.
		adult => 1,
	);
	$self->interface([
		{
			category => "Photo Options",
			fields   => [
				{ section => "Paths" },
				{
					name   => "http",
					label  => "Public photo path (over HTTP)",
					text   => "The path where photos are stored, relative to HTTP. Example: /static/photos",
					type   => "text",
				},
				{
					name   => "public",
					label  => "Private photo path (server filesystem)",
					text   => "The path where photos are stored relative to the server's filesystem. Example: ./static/photos",
					type   => "text",
				},

				{ section => "Photo Sizes" },
				{
					name   => "large",
					label  => "Large (full size)",
					text   => "The maximum width (in pixels) for the full-size version of a user's photo.",
					type   => "number",
				},
				{
					name   => "medium",
					label  => "Medium",
					text   => "The maximum width (in pixels) for the medium-size version of a user's photo.",
					type   => "number",
				},
				{
					name   => "small",
					label  => "Small",
					text   => "The maximum width (in pixels) for the small-size version of a user's photo.",
					type   => "number",
				},
				{
					name   => "tiny",
					label  => "Medium",
					text   => "The maximum width (in pixels) for the tiny-size version of a user's photo.",
					type   => "number",
				},
				{
					name   => "avatar",
					label  => "Avatar",
					text   => "The maximum width (in pixels) for the avatar-size version of a user's photo.",
					type   => "number",
				},
				{
					name   => "mini",
					label  => "Mini",
					text   => "The maximum width (in pixels) for the mini-size version of a user's photo.",
					type   => "number",
				},

				{ category => "Misc Settings" },
				{
					name   => "maximum",
					label  => "Maximum Photos Per User",
					text   => "The max number of photos a user can have (not enforced yet)",
					type   => "number",
				},
				{
					name   => "filesize",
					label  => "Maximum Upload File Size",
					text   => "The max file size for an uploaded photo, in bytes. 6 MB = 1024*1024*6 = 6291456.",
					type   => "number",
				},
				{
					name   => "adult",
					label  => "Adult Photos Allowed",
					type   => "checkgroup",
					options => [
						"1" => "Users can mark photos as 'adult'.",
					],
				},
			],
		}
	]);
}

=head1 METHODS

=head2 string public

Get the public path to photos, relative to index.cgi.

=cut

sub public {
	my $self = shift;
	return $self->{public};
}

=head2 string http

Get the public path to photos, relative to HTTP root.

=cut

sub http {
	my $self = shift;
	return $self->{http};
}

=head2 bool adultAllowed ()

Check whether adult photos are allowed.

=cut

sub adultAllowed {
	my $self = shift;
	return $self->{adult};
}

=head2 bool privatePermission ([href db], int owner, int context)

Check whether the owner of the photo album (C<owner>) has unlocked his private
photos for C<context> to view. This is a utility method used by all the photo
gathering methods below. If the C<context> is undefined or is 0 (guest user),
this method will always return false.

If you already have the owner's photo album DB open, you may pass it as the
first parameter, so that this method won't have to check twice.

Returns 1 or 0.

=cut

sub privatePermission {
	my $self = shift;
	my $db;
	if (ref($_[0]) eq "HASH") {
		$db = shift;
	}
	my $owner = shift;
	my $context = shift || '';

	# Sanitize.
	$owner   = Siikir::Util::stripID($owner);
	$context = Siikir::Util::stripID($context);

	# Same user is easy.
	use Carp qw(cluck);
	return 1 if length $context && $owner == $context;

	# Admins can see!
	return 1 if length $context && $self->Master->User->isAdmin($context);

	# Do we need to open the owner's DB?
	if (!defined $db) {
		if (!$self->Master->JsonDB->documentExists("photos/$owner")) {
			# No DB, return false.
			$@ = "No album DB found for user $owner.";
			return 0;
		}

		$db = $self->Master->JsonDB->getDocument("photos/$owner");
	}

	# Did the owner unlock for this user ID?
	if (!exists $db->{unlocked}) {
		$@ = "Owner doesn't have an unlocked list.";
		return 0;
	}
	if (exists $db->{unlocked}->{$context}) {
		return 1;
	}

	$@ = "No permission to view private photos.";
	return 0;
}

=head2 bool reportPhoto (int uid, int photoid, int context)

As part of the site's self moderation system, this method is used to report an
inappropriate B<public photo>. Reporting a public photo causes it to go into
the "pending approval" mode and the site admins are e-mailed to deal with it.

The C<context> is B<required> and it is the valid user ID of the user who
reports the photo. This is to keep track of reporters and track abuse of the
feature.

B<TODO>: the admin e-mail is hard coded into this function.

=cut

sub reportPhoto {
	my ($self,$uid,$pid,$context) = @_;
	$uid = Siikir::Util::stripID($uid);
	$pid = Siikir::Util::stripHex($pid);

	# All must exist.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "Photo owner ID doesn't exist.";
		return undef;
	}
	if (!$self->Master->User->userExists(id => $context)) {
		$@ = "Reporter user ID doesn't exist.";
		return undef;
	}

	my $photo = $self->getPhoto($uid, $pid, $context);
	if (!defined $photo) {
		$@ = "The photo you're reporting doesn't seem to exist.";
		return undef;
	}

	# A photo with the admin's blessing can't be flagged.
	if ($photo->{approved}) {
		$@ = "This photo has already been approved by an administrator.";
		return undef;
	}

	# A photo that has already been flagged can't be flagged again.
	if ($photo->{flagged}) {
		$@ = "This photo has already been reported by another user.";
		return undef;
	}

	# Private and adult pics are exempt.
	if ($photo->{private} || $photo->{adult}) {
		$@ = "Private photos and adult photos are exempt from being flagged.";
		return undef;
	}

	# Flag the photo.
	$self->updatePhoto($uid, $pid, flagged => 1);

	# Log the reporter's flagging statistics.
	my $acct = $self->Master->User->getAccount($context);
	foreach my $init (qw(flags_given flags_true flags_false)) {
		if (!exists $acct->{$init}) {
			$acct->{$init} = 0;
		}
	}

	# Log that the reporter has flagged a photo.
	$acct->{flags_given}++;
	$self->Master->User->setAccount($context, $acct);

	# Add it to the admin to-do list.
	my $db = [];
	if ($self->Master->JsonDB->documentExists("admin/flags")) {
		$db = $self->Master->JsonDB->getDocument("admin/flags");
	}
	push (@{$db}, {
		owner    => $uid,
		photo    => $pid,
		reporter => $context,
	});
	$self->Master->JsonDB->writeDocument("admin/flags", $db);

	# E-mail the admin.
	$self->Master->Messaging->email (
		email => 'root@localhost', #CONFIGME
		subject => "Photo Reported as Inappropriate by $acct->{username}",
		message => "Dear Administrators,\n\n"
			. "A public photo on Siikir.com has been reported as being inappropriate.\n\n"
			. "Please log in to your admin panel to decide the fate of the reported photo.\n"
			. "http://www.siikir.com/admin",
	);

	return 1;
}

=head2 aref getReports ([bool verbose])

Retrieve the list of reported public photos that an admin needs to review. With
C<verbose> provided, also pulls a lot of details about each report.

=cut

sub getReports {
	my ($self,$verbose) = @_;

	my $db = [];
	if ($self->Master->JsonDB->documentExists("admin/flags")) {
		$db = $self->Master->JsonDB->getDocument("admin/flags");
	}

	# Get more details?
	if ($verbose) {
		foreach my $report (@{$db}) {
			# Get the profiles and photos of each party.
			my $reporter_pro = $self->Master->Profile->getProfile($report->{reporter});
			my $victim_pro   = $self->Master->Profile->getProfile($report->{owner});
			my $photo        = $self->getPhoto($report->{owner}, $report->{photo});
			my $reporter_pic = $self->getProfilePhoto($report->{reporter});
			my $reporter_acct = $self->Master->User->getAccount($report->{reporter});
			my $victim_acct   = $self->Master->User->getAccount($report->{owner});

			# Fill out the report details.
			$report->{meta} = {
				reporter => $reporter_pro,
				victim   => $victim_pro,
				photo    => $photo,
			};
			$report->{meta}->{reporter}->{photo} = $reporter_pic->{avatar};
			$report->{meta}->{reporter}->{stats} = {
				flags_given => $reporter_acct->{flags_given} || 0,
				flags_true  => $reporter_acct->{flags_true}  || 0,
				flags_false => $reporter_acct->{flags_false} || 0,
			};
		}
	}

	return $db;
}

=head2 bool judgeReport (hash options)

Cast judgment on a reported photo. Options include:

  string judgment: either approve or deny
  int    owner: owner ID in the report
  string photo: photo ID in the report

On error this returns undef and sets C<$@>.

The result of the judgment is recorded in the reporter's history. If the photo
is denied, it is deleted. If it is approved, it is given the admin's approval
and can't be flagged again.

=cut

sub judgeReport {
	my ($self,%opts) = @_;

	my $judgment = $opts{judgment} || '';
	my $owner    = $opts{owner} || '';
	my $pid      = $opts{photo} || '';

	if ($judgment ne "approve" && $judgment ne "deny") {
		$@ = "Judgment of photos must be either: approve, or deny.";
		return undef;
	}

	# Look up the report in question.
	my $reports = $self->getReports();
	my $file    = undef; # This is the report in question
	my $new     = [];
	foreach my $report (@{$reports}) {
		if ($report->{owner} == $owner && $report->{photo} == $pid) {
			$file = $report;
			next;
		}
		push (@{$new}, $report);
	}

	# Not found?
	if (!defined $file) {
		$@ = "Can't look up that report.";
		return undef;
	}

	# Get the stats of the reporter.
	my $reporter = $self->Master->User->getAccount($file->{reporter});

	# Cast judgment.
	if ($judgment eq "approve") {
		# Give it the admin's blessing.
		$self->updatePhoto($owner, $pid, approved => 1);

		# Log the reporter's stats.
		$reporter->{flags_false}++;
	}
	else {
		# Delete the photo.
		$self->deletePhoto($owner, $pid);

		# Log the reporter's stats.
		$reporter->{flags_true}++;
	}

	# Save the reporter's stats.
	$self->Master->User->setAccount($file->{reporter}, $reporter);

	# Save the new pending list.
	$self->Master->JsonDB->writeDocument("admin/flags", $new);

	return 1;
}

=head2 array getAlbums (int uid[, int context])

Retrieve a list of all of a user's albums. Returns an array of hashes for each
album, in alphabetical order by album name.

The C<context> is the user ID of the user who wants to see the albums. This is
to take into account private photo support.

=cut

sub getAlbums {
	my ($self,$uid,$context) = @_;
	$uid = Siikir::Util::stripID($uid);
	$context = Siikir::Util::stripID($context);

	# User must exist.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "The user ID $uid wasn't found!";
		return undef;
	}

	# Fetch their album configuration.
	if (!$self->Master->JsonDB->documentExists("photos/$uid")) {
		$@ = "No album information for ID $uid!";
		return undef;
	}
	my $db = $self->Master->JsonDB->getDocument("photos/$uid");

	# Get permissions.
	my $private = $self->privatePermission($db, $uid, $context);

	# Construct the return list.
	my $return = [];
	foreach my $album (sort { $a cmp $b } keys %{$db->{albums}}) {
		# Count all the public photos in it (and private ones if allowed).
		my $photos  = 0;
		my $priv    = 0;
		foreach my $pid (@{$db->{order}->{$album}}) {
			# Private?
			if ($db->{albums}->{$album}->{$pid}->{private}) {
				# Permission to view?
				next unless $private;
				$priv++;
			}
			$photos++;
		}

		# Skip all-private albums.
		next unless $photos > 0;

		# If this album's cover picture is private and we can't view it, get rid of it.
		my $cover = $db->{albums}->{$album}->{ $db->{covers}->{$album} } || undef;
		if (defined $cover && $cover->{private} && !$private) {
			$cover = undef;
		}
		elsif (defined $cover && $cover->{adult}) {
			$cover = undef;
		}
		elsif (defined $cover && $cover->{flagged} && !$cover->{approved}) {
			$cover = undef;
		}

		push (@{$return}, {
			name    => $album,
			cover   => $cover,
			size    => $photos,
			private => ($photos == $priv ? 1 : 0), # whether ALL PHOTOS are private!
		});
	}

	return $return;
}

=head2 array getAlbum (int uid, string album-id, int context)

Retrieve a user's full album. Returns an array of hashes: the array maintains
the order of the photos in the album, and each hash is the data for the photos
in the album (the same data as you would get from getPhoto).

Returns undef and sets $@ when the album is invalid.

=cut

sub getAlbum {
	my ($self,$uid,$aid,$context) = @_;
	$uid = Siikir::Util::stripID($uid);
	$aid = Siikir::Util::stripSimple($aid);

	# User must exist.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "The user ID $uid wasn't found!";
		return undef;
	}

	# Fetch their album configuration.
	if (!$self->Master->JsonDB->documentExists("photos/$uid")) {
		$@ = "No album information for ID $uid!";
		return undef;
	}
	my $db = $self->Master->JsonDB->getDocument("photos/$uid");

	# Private permissions.
	my $private = $self->privatePermission($db, $uid, $context);

	# Album exists, right?
	if (!exists $db->{order}->{$aid}) {
		$@ = "Album '$aid' not found for user $uid!";
		return undef;
	}

	# Prepare the array of results.
	my $result = [];
	foreach my $pid (@{$db->{order}->{$aid}}) {
		next unless exists $db->{albums}->{$aid}->{$pid};

		# Skip private photos if we can't view them.
		if ($db->{albums}->{$aid}->{$pid}->{private} && !$private) {
			next;
		}

		push (@{$result}, $db->{albums}->{$aid}->{$pid});
	}

	return $result;
}

=head2 hash getProfilePhoto (int uid)

Fetch only the details about the user's profile picture. Returns an empty hash
when they don't have a profile picture set, or undef on error.

=cut

sub getProfilePhoto {
	my ($self,$uid) = @_;
	$uid = Siikir::Util::stripID($uid);

	# User must exist.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "The user ID $uid wasn't found!";
		return undef;
	}

	# Fetch their album configuration.
	if (!$self->Master->JsonDB->documentExists("photos/$uid")) {
		$@ = "No album information for ID $uid!";
		return undef;
	}
	my $db = $self->Master->JsonDB->getDocument("photos/$uid");

	# Get their profile photo.
	my $profile = $db->{profile};
	return {} unless defined $profile;
	my $photo   = $self->getPhoto($uid, $profile);
	if (!defined $photo) {
		return {};
	}

	return $photo;
}

=head2 hash getPhoto (int uid, string photo-id, int context)

Retrieve information about a specific photo from a user's albums.

=cut

sub getPhoto {
	my ($self,$uid,$pid,$context) = @_;
	$uid     = Siikir::Util::stripID($uid);
	$pid     = Siikir::Util::stripHex($pid);
	$context = Siikir::Util::stripID($context);

	# User must exist.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "The user ID $uid wasn't found!";
		return undef;
	}

	# Fetch their album configuration.
	if (!$self->Master->JsonDB->documentExists("photos/$uid")) {
		$@ = "No album information for ID $uid!";
		return undef;
	}
	my $db = $self->Master->JsonDB->getDocument("photos/$uid");

	# Get private permissions.
	my $private = $self->privatePermission($db, $uid, $context);

	# What album is the photo in?
	if (!exists $db->{map}->{$pid}) {
		$@ = "That photo was not found.";
		return undef;
	}
	my $album = $db->{map}->{$pid};

	# Last minute sanity check.
	if (!exists $db->{albums}->{$album}->{$pid}) {
		$@ = "The photo was not found in the album it claimed to be from!";
		return undef;
	}

	# A private photo that we can't view?
	if ($db->{albums}->{$album}->{$pid}->{private} && !$private) {
		$@ = "You do not have permission to view that photo.";
		return undef;
	}

	# Injection additional information into the data:
	# What position it's at in the album, how many photos total,
	# and the photo IDs of its siblings.
	my @siblings = ();
	foreach my $pic (@{$db->{order}->{$album}}) {
		# Skip private ones.
		if ($db->{albums}->{$album}->{$pic}->{private} && !$private) {
			next;
		}
		push (@siblings, $pic);
	}

	# Prepare the return info. Loop over only siblings we can see.
	my $return = $db->{albums}->{$album}->{$pid};
	for (my $i = 0; $i < scalar @siblings; $i++) {
		if ($siblings[$i] eq $pid) {
			# We found us! Find the sublings. Skip private siblings we can't see.
			my ($prev,$next);
			if ($i == 0) {
				# We're the first photo. So previous is the last!
				$prev = $siblings[-1];
				$next = scalar @siblings > ($i + 1) ? $siblings[$i+1] : $pid;
			}
			elsif ($i == (scalar @siblings - 1)) {
				# We're the last photo. So next is the first!
				$prev = $siblings[$i - 1];
				$next = $siblings[0];
			}
			else {
				# Right in the middle.
				$prev = $siblings[$i - 1];
				$next = $siblings[$i + 1];
			}

			# Inject.
			$return->{position} = $i + 1;
			$return->{siblings} = scalar @siblings;
			$return->{previous} = $prev;
			$return->{next}     = $next;
		}
	}

	# Return the info.
	return $return;
}

=head2 bool setDefault (int uid, string photo-id)

Set a user's default photo to their photo named C<photo-id>. The user must own
the photo.

=cut

sub setDefault {
	my ($self,$uid,$pid) = @_;
	$uid = Siikir::Util::stripID($uid);
	$pid = Siikir::Util::stripHex($pid);

	# User must exist.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "The user ID $uid wasn't found!";
		return undef;
	}

	# Fetch their album configuration.
	if (!$self->Master->JsonDB->getDocument("photos/$uid")) {
		$@ = "No album information for ID $uid!";
		return undef;
	}
	my $db = $self->Master->JsonDB->getDocument("photos/$uid");

	# We can find the photo?
	if (!exists $db->{map}->{$pid}) {
		$@ = "That photo was not found.";
		return undef;
	}
	my $album = $db->{map}->{$pid};

	# Sanity check.
	if (!exists $db->{albums}->{$album}->{$pid}) {
		$@ = "Couldn't find photo in album!";
		return undef;
	}

	# Can't set an adult photo.
	if ($db->{albums}->{$album}->{$pid}->{adult}) {
		$@ = "You can't set an adult picture as your profile picture.";
		return undef;
	}
	elsif ($db->{albums}->{$album}->{$pid}->{private}) {
		# A private picture as profile picture? This means no profile picture.
		delete $db->{profile};
	}
	else {
		# Update the default photo.
		$db->{profile} = $pid;
	}

	# Write changes.
	$self->Master->JsonDB->writeDocument("photos/$uid", $db);

	# Rebuild the search cache.
	$self->Master->Search->buildCache();
	return 1;
}

=head2 bool setCover (int uid, string album-id, string photo-id)

Change an album's cover picture to a picture from within that album.

=cut

sub setCover {
	my ($self,$uid,$aid,$pid) = @_;
	$uid = Siikir::Util::stripID($uid);
	$aid = Siikir::Util::stripSimple($aid);
	$pid = Siikir::Util::stripHex($pid);

	# User must exist.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "The user ID $uid wasn't found!";
		return undef;
	}

	# Fetch their album configuration.
	if (!$self->Master->JsonDB->getDocument("photos/$uid")) {
		$@ = "No album information for ID $uid!";
		return undef;
	}
	my $db = $self->Master->JsonDB->getDocument("photos/$uid");

	# We can find the photo?
	if (!exists $db->{map}->{$pid}) {
		$@ = "That photo was not found.";
		return undef;
	}
	if ($db->{map}->{$pid} ne $aid) {
		$@ = "That photo belongs to a different album.";
	}

	# Update the cover photo.
	$db->{covers}->{$aid} = $pid;

	# Write changes.
	$self->Master->JsonDB->writeDocument("photos/$uid", $db);
	return 1;
}

=head2 bool updatePhoto (int uid, string photo-id, hash options)

Update options about a user's photo. Valid options are:

  caption
  private
  adult
  approved
  flagged

=cut

sub updatePhoto {
	my ($self,$uid,$pid,%opts) = @_;
	$uid = Siikir::Util::stripID($uid);
	$pid = Siikir::Util::stripHex($pid);

	# User must exist.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "The user ID $uid wasn't found!";
		return undef;
	}

	# Fetch their album configuration.
	if (!$self->Master->JsonDB->getDocument("photos/$uid")) {
		$@ = "No album information for ID $uid!";
		return undef;
	}
	my $db = $self->Master->JsonDB->getDocument("photos/$uid");

	# We can find the photo?
	if (!exists $db->{map}->{$pid}) {
		$@ = "That photo was not found.";
		return undef;
	}
	my $album = $db->{map}->{$pid};

	# Sanity check.
	if (!exists $db->{albums}->{$album}->{$pid}) {
		$@ = "Couldn't find photo inside album!";
		return undef;
	}

	# Sanitize inputs.
	if (exists $opts{caption}) {
		my $caption = Siikir::Util::stripHTML($opts{caption});
		$db->{albums}->{$album}->{$pid}->{caption} = $caption;
	}
	if (exists $opts{private}) {
		$db->{albums}->{$album}->{$pid}->{private} = $opts{private} ? 1 : 0;
	}
	if (exists $opts{adult}) {
		$db->{albums}->{$album}->{$pid}->{adult} = $opts{adult} ? 1 : 0;
	}
	if (exists $opts{approved}) {
		$db->{albums}->{$album}->{$pid}->{approved} = $opts{approved} ? 1 : 0;
	}
	if (exists $opts{flagged}) {
		$db->{albums}->{$album}->{$pid}->{flagged} = $opts{flagged} ? 1 : 0;
	}

	# Replacing file names.
	foreach my $fn (qw(large medium small avatar tiny mini)) {
		if (exists $opts{$fn}) {
			$db->{albums}->{$album}->{$pid}->{$fn} = $opts{$fn};
		}
	}

	# Write changes.
	$self->Master->JsonDB->writeDocument("photos/$uid", $db);
	return 1;
}

=head2 bool arrangePhotos (int uid, string album-id, aref order)

Rearrange the order of the photos in the album. C<order> is an array reference
containing the list of photo ID's in that album. Any IDs that don't exist will
be ignored, and any that weren't mentioned will be ordered at the end
automatically (to protect against various error cases).

=cut

sub arrangePhotos {
	my ($self,$uid,$aid,$order) = @_;
	$uid = Siikir::Util::stripID($uid);
	$aid = Siikir::Util::stripSimple($aid);

	# Sanity checks.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "The user ID $uid wasn't found!";
		return undef;
	}
	if (!$self->Master->JsonDB->documentExists("photos/$uid")) {
		$@ = "No album information for user $uid!";
		return undef;
	}
	my $db = $self->Master->JsonDB->getDocument("photos/$uid");

	# Album exists?
	if (!exists $db->{albums}->{$aid}) {
		$@ = "The album '$aid' wasn't found!";
		return undef;
	}

	# Get the original sort order.
	my $orig = $db->{order}->{$aid};
	my $map  = { map { $_ => 1 } @{$orig} };

	# Create the new order.
	my $new = [];
	foreach my $pid (@{$order}) {
		# Only if it exists in the album!
		if (exists $map->{$pid}) {
			# Add it to the new list, and remove from the map.
			push (@{$new}, $pid);
			delete $map->{$pid};
		}
	}

	# Any photos not represented?
	if (scalar(keys(%{$map}))) {
		# Add them to the end. Order doesn't really matter, this is an error case.
		foreach my $pid (keys %{$map}) {
			push (@{$new}, $pid);
		}
	}

	# Update it!
	$db->{order}->{$aid} = $new;
	$self->Master->JsonDB->writeDocument("photos/$uid", $db);
	return 1;
}

=head2 bool deletePhoto (int uid, string photo-id)

Completely delete a user's photo.

=cut

sub deletePhoto {
	my ($self,$uid,$pid,%opts) = @_;
	$uid = Siikir::Util::stripID($uid);
	$pid = Siikir::Util::stripHex($pid);

	# User must exist.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "The user ID $uid wasn't found!";
		return undef;
	}

	# Fetch their album configuration.
	if (!$self->Master->JsonDB->documentExists("photos/$uid")) {
		$@ = "No album information for ID $uid!";
		return undef;
	}
	my $db = $self->Master->JsonDB->getDocument("photos/$uid");

	# We can find the photo?
	if (!exists $db->{map}->{$pid}) {
		$@ = "That photo was not found.";
		return undef;
	}
	my $album = $db->{map}->{$pid};

	# Sanity check.
	if (!exists $db->{albums}->{$album}->{$pid}) {
		$@ = "Couldn't find photo inside album!";
		return undef;
	}

	$self->debug("Completely deleting photo $pid from user $uid");

	# We need to untaint the "public" variable. This comes from server side DB so
	# we trust that the admin has entered it safely.
	my ($public) = ($self->{public} =~ /^(.+?)$/);

	# Delete all image files.
	foreach my $size (qw(large medium small avatar tiny mini)) {
		my $pic = Siikir::Util::stripSimple($db->{albums}->{$album}->{$pid}->{$size});
		$self->debug("Delete: $pic");
		unlink("$public/$pic");
	}

	# Delete it from the sort etc.
	my @neworder = ();
	foreach my $pic (@{$db->{order}->{$album}}) {
		next if $pid eq $pic;
		push (@neworder, $pic);
	}
	$db->{order}->{$album} = [ @neworder ];
	delete $db->{map}->{$pid};
	delete $db->{albums}->{$album}->{$pid};

	# Was this pic our profile picture?
	if ($db->{profile} eq $pid) {
		# No more profile picture.
		delete $db->{profile};
	}
	if ($db->{covers}->{$album} eq $pid) {
		# Try to use a different photo.
		if (scalar @{$db->{order}->{$album}} > 0) {
			$db->{covers}->{$album} = $db->{order}->{$album}->[0];
		}
	}

	# If the album is empty now too, delete it as well.
	if (scalar keys %{$db->{albums}->{$album}} == 0) {
		delete $db->{albums}->{$album};
		delete $db->{order}->{$album};
		delete $db->{covers}->{$album};
	}

	# Write changes.
	$self->Master->JsonDB->writeDocument("photos/$uid", $db);
	return 1;
}

=head2 bool unlockPrivate (int uid, int for)

Unlock all the private photos owned by C<uid>, so that the user ID C<for> can
view them all. Also, a message is sent to C<for> to notify them of this.

=cut

sub unlockPrivate {
	my ($self,$uid,$for) = @_;
	$uid = Siikir::Util::stripID($uid);
	$for = Siikir::Util::stripID($for);

	# User must exist.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "The user ID $uid wasn't found!";
		return undef;
	}
	elsif (!$self->Master->User->userExists(id => $for)) {
		$@ = "The user ID $uid wasn't found!";
		return undef;
	}

	# Fetch their album configuration.
	if (!$self->Master->JsonDB->getDocument("photos/$uid")) {
		$@ = "No album information for ID $uid!";
		return undef;
	}
	my $db = $self->Master->JsonDB->getDocument("photos/$uid");

	# Add the user to the unlocked list.
	$db->{unlocked}->{$for} = 1;

	# Write changes.
	$self->Master->JsonDB->writeDocument("photos/$uid", $db);

	# Notify the recipient.
	my $sender = $self->Master->Profile->getProfile($uid);
	my $recip  = $self->Master->Profile->getProfile($for);
	$self->Master->Messaging->sendMessage (
		from    => $uid,
		to      => $for,
		subject => "I have unlocked my private photos for you!",
		message => "Hello $recip->{displayname},\n\n"
			. "I have unlocked my private photos for you! You can view them "
			. "by going to my profile and clicking on \"View Photos\".",
	);
	return 1;
}

=head2 bool lockPrivate (int uid, int from)

Lock the user C<from> from viewing the private photos of C<uid>.

=cut

sub lockPrivate {
	my ($self,$uid,$for) = @_;
	$uid = Siikir::Util::stripID($uid);
	$for = Siikir::Util::stripID($for);

	# User must exist.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "The user ID $uid wasn't found!";
		return undef;
	}
	elsif (!$self->Master->User->userExists(id => $for)) {
		$@ = "The user ID $uid wasn't found!";
		return undef;
	}

	# Fetch their album configuration.
	if (!$self->Master->JsonDB->getDocument("photos/$uid")) {
		$@ = "No album information for ID $uid!";
		return undef;
	}
	my $db = $self->Master->JsonDB->getDocument("photos/$uid");

	# Re-lock the photos.
	delete $db->{unlocked}->{$for};

	# Write changes.
	$self->Master->JsonDB->writeDocument("photos/$uid", $db);
	return 1;
}

=head2 aref unlockedList (int uid)

Retrieve a list of all the user IDs that C<uid> has unlocked his photos for.

=cut

sub unlockedList {
	my ($self,$uid) = @_;
	$uid = Siikir::Util::stripID($uid);

	# User must exist.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "The user ID $uid wasn't found!";
		return undef;
	}

	# Fetch their album configuration.
	if (!$self->Master->JsonDB->getDocument("photos/$uid")) {
		$@ = "No album information for ID $uid!";
		return undef;
	}
	my $db = $self->Master->JsonDB->getDocument("photos/$uid");

	return [] unless exists $db->{unlocked};
	return [ sort { $a <=> $b } keys %{$db->{unlocked}} ];
}


=head2 bool uploadPhoto (int uid, hash options)

Upload a photo to the user's photo album. Options include:

  location: Where the photo is (file, www)
  filename: File name or URL of incoming photo
  handle:   A file handle (from CGI::upload), if applicable
  url:      The URL to the file, if applicable
  album:    Album name to put the photo into (default "Photos")
  caption:  The caption on the photo.
  private:  1 or 0, the privacy setting of the photo
  adult:    1 or 0, the adult setting of the photo

Returns the photo ID (true) success, undef and sets C<$@> on error.

=cut

sub uploadPhoto {
	my ($self,$uid,%opts) = @_;
	$uid = Siikir::Util::stripID($uid);

	# User exists?
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "The user ID $uid wasn't found!";
		return undef;
	}

	# Fetch their album configuration.
	my $db = {};
	if ($self->Master->JsonDB->documentExists("photos/$uid")) {
		$db = $self->Master->JsonDB->getDocument("photos/$uid");
	}

	# Get options.
	my $album    = delete $opts{album} || "Photos";
	my $name     = delete $opts{filename};
	my $location = delete $opts{location};
	my $caption  = delete $opts{caption} || "";
	my $private  = delete $opts{private} || 0;
	my $adult    = delete $opts{adult} || 0;

	# Get rid of any possible references on filename (may be an Fh type on upload)
	$name = "$name";

	# Strip nasties.
	$album   = Siikir::Util::stripSimple($album);
	$caption = Siikir::Util::stripHTML($caption);

	# Make sure it's a valid file.
	if ($name !~ /\.(jpe?g|gif|png)$/i) {
		$@ = "Invalid file type ($name)!";
		return undef;
	}

	# Fetch the photo.
	my $bin;
	if ($location eq "www") {
		# It's on the web. Fetch it with libwww-perl.
		my $ua = LWP::UserAgent->new();
		$ua->agent($self->{agent});

		# Security related options for LWP.
		$ua->timeout(15);                                   # Only try for 15 seconds to get the image.
		$ua->max_size($self->{filesize});                   # Limit how much data we pull down
		$ua->protocols_allowed([ 'http', 'https', 'ftp' ]); # Only allow web URIs

		# Get a response.
		my $resp = $ua->get($name);
		if ($resp->is_success) {
			$bin = $resp->content;
			if (length $bin < $resp->header("Content-Length")) {
				$@ = "The file size on the remote server is too large.";
				return undef;
			}
			elsif (length $bin == 0) {
				$@ = "Got an empty file from the remote server.";
				return undef;
			}
		}
		else {
			# An error.
			$@ = "Remote server said: " . $resp->status_line();
			return undef;
		}
	}
	elsif ($location eq "pc") {
		# On the user's filesystem.
		my $handle = delete $opts{handle} || do {
			$@ = "No filehandle given for uploaded photo!";
			return undef;
		};

		# Read from the filehandle.
		my $buffer;
		while (read($handle, $buffer, 1024)) { #<$handle>) {
			$bin .= $buffer;
			if (length $bin > $self->{filesize}) {
				$@ = "Uploaded file size is too large.";
				return undef;
			}
		}
	}
	else {
		$@ = "Unknown location '$location'!";
		return undef;
	}

	# Save it to a temporary file.
	my ($ext) = ($name =~ /\.(jpe?g|gif|png)$/i);
	my ($public) = ($self->{public} =~ /^(.+?)$/);
	my $temp = "$public/$uid-temp.$ext";
	$self->debug("Uploading photo for UID $uid. Save it as temp: $temp");
	open (my $fh, ">", $temp) or do {
		$@ = "Can't write to temp file $temp: $@";
		return undef;
	};
	binmode $fh;
	print {$fh} $bin;
	close ($fh);

	# Scale it down to each size.
	my %sizes = ();
	foreach my $size (qw(large medium small tiny avatar mini)) {
		$sizes{$size} = $self->resizePhoto ($temp, $size);
	}

	# Delete the temporary file.
	unlink($temp);

	# Make up a unique public key for this set of photos.
	my $key = md5_hex(time());
	while (exists $db->{map}->{$key}) {
		$key = md5_hex(int(rand(999_999)));
	}

	# Update their photo album configuration.
	$db->{albums}->{$album}->{$key} = {
		ip       => $ENV{REMOTE_ADDR},
		key      => $key,
		uploaded => time(),
		album    => $album,
		name     => $name,
		caption  => $caption,
		private  => $private,
		adult    => $adult,
		flagged  => 0, # When a user flags the pic inappropriate
		approved => 0, # When an admin overrides the flag
		%sizes,
	};
	$db->{albums}->{$album}->{$key}->{name} = $name;

	# Maintain the upload order.
	if (!exists $db->{order}->{$album}) {
		$db->{order}->{$album} = [];
	}
	unshift (@{$db->{order}->{$album}}, $key);

	# Maintain a photo-to-album map.
	$db->{map}->{$key} = $album;

	# Set the album cover?
	if (!exists $db->{covers}->{$album}) {
		$db->{covers}->{$album} = $key;
	}

	# Set the profile picture?
	my $recache = 0;
	if (!exists $db->{profile} && !$adult && !$private) {
		$db->{profile} = $key;

		# Rebuild the search cache.
		$recache = 1;
	}

	# Save their photo DB.
	$self->Master->JsonDB->writeDocument("photos/$uid", $db);

	# Need to rebuild search cache?
	if ($recache) {
		$self->Master->Search->buildCache();
	}
	return $key;
}

=head2 bool cropPhoto (int uid, string photo-id, hash options)

Delete a user's thumbnails and regenerate them with a new crop value.

Options include:

  int x, y: Coords to begin the crop
  int size: Size of one edge of the square.

=cut

sub cropPhoto {
	my ($self,$uid,$pid,%opts) = @_;
	$uid = Siikir::Util::stripID($uid);
	$pid = Siikir::Util::stripHex($pid);

	# User must exist.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "The user ID $uid wasn't found!";
		return undef;
	}

	# Fetch their album configuration.
	if (!$self->Master->JsonDB->getDocument("photos/$uid")) {
		$@ = "No album information for ID $uid!";
		return undef;
	}
	my $db = $self->Master->JsonDB->getDocument("photos/$uid");

	# We can find the photo?
	if (!exists $db->{map}->{$pid}) {
		$@ = "That photo was not found.";
		return undef;
	}
	my $album = $db->{map}->{$pid};

	# Sanity check.
	if (!exists $db->{albums}->{$album}->{$pid}) {
		$@ = "Couldn't find photo inside album!";
		return undef;
	}

	$self->debug("Recropping photo $pid from user $uid");

	# Delete all image files except large. Detaint public.
	my ($public) = ($self->{public} =~ /^(.+?)$/);
	foreach my $size (qw(medium small avatar tiny mini)) {
		my $pic = Siikir::Util::stripSimple($db->{albums}->{$album}->{$pid}->{$size});
		$self->debug("Delete: $pic");
		unlink("$public/$pic");
	}

	# Regenerate all the thumbnails.
	my $large = $db->{albums}->{$album}->{$pid}->{large};
	foreach my $size (qw(medium small avatar tiny mini)) {
		my $pic = $self->resizePhoto ("$self->{public}/$large", $size,
			'x'    => $opts{x},
			'y'    => $opts{y},
			'size' => $opts{size},
		);
		$db->{albums}->{$album}->{$pid}->{$size} = $pic;
	}

	# Write changes.
	$self->Master->JsonDB->writeDocument("photos/$uid", $db);

	# Was this their profile picture? If so, rebuild the search cache.
	if ($db->{profile} eq $pid) {
		$self->Master->Search->buildCache();
	}

	return 1;
}

=head2 string resizePhoto (string photopath, string size[, hash options])

Resize a temporary photo at C<photopath> into the specified C<size>,
and return the file name of the newly created file.

The optional C<options> are used for creating the square thumbnail images. Values
accepted are:

  string filename: The target filename (instead of generating a new name),
                   for modifying an existing photo.
  int x, y:  Coords where to start the crop at.
  int size:  Length of one side of the square.

If the given coordinates are impossible (i.e. if the photo is 300 pixels wide
and you try to make a 100 pixel square but set x=250, the square will be adjusted
down to 50 pixels to fit).

If no options are given, the first largest square will be cropped automatically.

=cut

sub resizePhoto {
	my ($self,$temp,$size,%opts) = @_;

	# Untaint the public folder.
	my ($public) = ($self->{public} =~ /^(.+?)$/);

	$self->debug("Resize temp $temp to size: $size");

	# Find out the type of file.
	my $type = "";
	my $ext  = "";
	if ($temp =~ /\.jpe?g$/i) {
		$type = "JPEG";
		$ext  = "jpg";
	}
	elsif ($temp =~ /\.gif$/i) {
		$type = "GIF";
		$ext  = "gif";
	}
	elsif ($temp =~ /\.png$/i) {
		$type = "PNG";
		$ext  = "png";
	}
	else {
		# This is fatal!
		die "Can't determine image type for $temp!";
	}

	# Load the source image.
	my $image = Image::Magick->new();
	my $X = $image->Read($temp);
	$self->debug("$X") if $X;

	# Make up a unique file name.
	my $uid;
	if ($opts{filename}) {
		$self->debug("Using given unique filename: $opts{filename}");
		$uid = Siikir::Util::stripHex($opts{filename});
	}
	else {
		$uid = md5_hex(int(rand(999_999_999))) . ".$ext";
		while (-f "$self->{public}/$uid") {
			$uid = md5_hex(int(rand(999_999_999))) . ".$ext";
		}
	}

	$self->debug("Generated unique filename: $uid");

	# Get the image dimensions.
	my $origWidth = $image->Get('width');
	my $origHeight = $image->Get('height');
	my $newWidth  = $self->{$size};
	$self->debug("Original image width: $origWidth, height: $origHeight (target size: $newWidth)");

	# For the large version, only scale it, don't crop it.
	if ($size eq "large") {
		# Do we NEED to?
		if ($origWidth <= $newWidth) {
			$self->debug("Don't need to scale down the large photo.");
			copy($temp, "$public/$uid");
			return $uid;
		}
		my $ratio = $newWidth / $origWidth;
		my $newHeight = int($origHeight * $ratio);
		$self->debug("Resize large image to $newWidth x $newHeight");

		$X = $image->Resize (
			width  => $newWidth,
			height => $newHeight,
			#blur   => 0,
		);
		$self->debug("Resize error - $X") if $X;

		# Write it.
		$image->Write("$public/$uid");
		return $uid;
	}

	# Get the coords.
	my $x = $opts{x} || 0;
	my $y = $opts{y} || 0;
	my $len = $opts{size} || ($origWidth > $origHeight ? $origHeight : $origWidth);
	$self->debug("Coords: x=$x y=$y size=$len (opts size: $opts{size})");

	# Adjust the coords if impossible.
	if ($x < 0) {
		$self->debug("X-coord is less than 0; fixing!");
		$x = 0;
	}
	if ($y < 0) {
		$self->debug("Y-coord is less than 0; fixing!");
		$y = 0;
	}
	if ($x > $origWidth) {
		$self->debug("X-coord is greater than image width; fixing!");
		$x = $origWidth - $len;
		$x = 0 if $x < 0;
	}
	if ($y > $origHeight) {
		$self->debug("Y-coord is greater than image height; fixing!");
		$y = $origHeight - $len;
		$y = 0 if $y < 0;
	}
	if ($x + $len > $origWidth) {
		$self->debug("Requested box is outside the right edge of the image");
		my $diff = $x + $len - $origWidth;
		$self->debug("OOB by: $diff");
		$len -= $diff;
	}
	if ($y + $len > $origHeight) {
		$self->debug("Requested box is outside the bottom edge of the image");
		my $diff = $y + $len - $origHeight;
		$self->debug("OOB by: $diff");
		$len -= $diff;
	}

	if ($newWidth == $len) {
		# It doesn't need to be resized!
		$self->debug("This image is already the perfect size!");
		copy ($temp, "$public/$uid");
		return $uid;
	}

	# Crop the image to the requested box.
	my $geometry = "${size}x${size}+${x}+${y}";
	$self->debug("Crop image to $x,$y + $len (or: $geometry)");
	$X = $image->Crop (
		geometry => "${len}x${len}+${x}+${y}",
	);
	$self->debug("Crop error: $X") if $X;

	# Scale it.
	$self->debug("New image width: " . $image->Get('width'));
	$self->debug("Resize image to $newWidth x $newWidth");
	$X = $image->Resize (
		width  => $newWidth,
		height => $newWidth,
		#blur   => ($origWidth > $newWidth || $origHeight > $newWidth) ? 1 : 0,
	);
	$self->debug("Resize error - $X") if $X;

	# Write it.
	$image->Write("$public/$uid");
	return $uid;
}

1;
