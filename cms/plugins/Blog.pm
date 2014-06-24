package Siikir::Plugin::Blog 2011.0930;

use 5.14.0;
use strict;
use warnings;

use base "Siikir::Plugin";

=head1 NAME

Siikir::Plugin::Blog - Web blogs for the users.

=cut

sub init {
	my $self = shift;

	$self->debug("Blog plugin loaded!");
	$self->requires(qw(Photo Emoticons));

	# Options.
	$self->options(
		# Default category (tag, channel) of blog entries.
		category => "Uncategorized",

		# Path to public avatar directory.
		avatars_pub => "/static/avatars",  # public html path
		avatars_pri => "./static/avatars", # local filesystem path

		# Are only admins allowed to have blogs?
		adminonly => 1,

		# Default privacy setting for new posts.
		privacy  => "public",

		# Default setting for rendering emoticons.
		emoticons => 1, # enabled

		# Number of posts to display per page.
		ppp => 5,

		# Number of posts to display in RSS feed.
		feed => 5,

		# Smilie theme.
		smilies => 'default',

		# Time stamp format, in Time::Format syntax.
		timestamp => "Weekday, Month dd yyyy @ H:mm:ss AM",

		# Allow guests to comment on blogs.
		guests => 1,

		# Require CAPTCHA to leave comments by guests.
		captcha => 0,

		# Vocabulary.
		subject    => "(no subject)", # default when no subject given
		previous   => "Previous Entry",
		next       => "Next Entry",
		newer      => "Newer",
		older      => "Older",
		comment    => "Leave a comment",
		single     => "# comment",
		multiple   => "# comments",
		permalink  => "Permalink",
		categories => "Categories",
	);

	# Option interface.
	$self->interface([
		{
			category => "Blog Settings",
			fields   => [
				{ section => "Defaults" },
				{
					name    => "category",
					label   => "Default Category",
					text    => "This category is used when none are defined for a blog entry.",
					type    => "text",
				},
				{
					name    => "privacy",
					label   => "Default Privacy",
					text    => "The default privacy setting for new blog posts.",
					type    => "radio",
					options => [
						"public"  => "Public",
						"private" => "Private",
						"members" => "Members only",
						"friends" => "Friends only",
					],
				},
				{
					name    => "emoticons",
					label   => "Enable Emoticons",
					type    => "checkgroup",
					options => [
						"1" => "Enable emoticons by default",
					],
				},

				{ section => "Paths" },
				{
					name    => "avatars_pri",
					label   => "Avatar Path (filesystem)",
					text    => "The path to the avatars on the server side (local filesystem path, probably like ./static/avatars)",
					type    => "text",
				},
				{
					name    => "avatars_pub",
					label   => "Avatar Path (over HTTP)",
					text    => "The path to the avatars over HTTP (probably like /static/avatars)",
					type    => "text",
				},

				{ section => "Misc Options" },
				{
					name    => "adminonly",
					label   => "Admin Only",
					text    => "Only admin users can have blogs.",
					type    => "checkgroup",
					options => [
						"1" => "Admin only",
					],
				},
				{
					name    => "guests",
					label   => "Guest Comments",
					text    => "Allow guests to comment on blogs.",
					type    => "checkgroup",
					options => [
						"1" => "Enable",
					],
				},
				{
					name    => "timestamp",
					label   => "Timestamp Format",
					type    => "text",
				},
				{
					name    => "ppp",
					label   => "Posts Per Page",
					type    => "number",
				},
				{
					name    => "feed",
					label   => "Posts Per RSS Feed",
					type    => "number",
				},
			],
		},
	]);
}

=head1 METHODS

=head2 int entriesPerPage ()

Returns the number of entries per page.

=cut

sub entriesPerPage {
	my $self = shift;
	return $self->{ppp};
}

=head2 bool adminOnly ()

Returns whether only admins can have blogs.

=cut

sub adminOnly {
	my $self = shift;
	return $self->{adminonly};
}

=head2 hash getVocabulary ()

Returns the vocabulary.

=cut

sub getVocabulary {
	my $self = shift;

	my %vocab;
	foreach my $key (qw(subject previous next newer older comment single multiple permalink categories)) {
		$vocab{$key} = $self->{$key};
	}
	return %vocab;
}

=head2 string avatarHttp ()

Return the HTTP path where the avatars are kept.

=cut

sub avatarHttp {
	my $self = shift;
	return $self->{avatars_pub};
}

=head2 array getAvatars ()

Retrieve the list of public, shared, blog avatars that users can select instead
of using their profile picture.

=cut

sub getAvatars {
	my $self = shift;
	my @avatars = ();

	opendir (DIR, $self->{avatars_pri});
	foreach my $image (sort(grep(/\.(jpe?g|gif|png)$/i, readdir(DIR)))) {
		push (@avatars, $image);
	}
	closedir (DIR);

	return @avatars;
}

=head2 data getIndex (int uid[, int context])

Get the blog index for the user. Returns a hash of hashes for every blog post
the user has. Each hash has the format of:

  {
    id:         ID number for the blog post
    fid:        friendly ID for the blog post (for the URLs)
    time:       epoch time when the post was published
    sticky:     The "stickiness" of the post (sticky posts show up first on global views)
    author:     The author user ID of the post
    categories: arrayref of categories
    privacy:    the privacy setting
    subject:    the post subject
  }

Keys in the top level hash are the blog IDs.

=cut

sub getIndex {
	my ($self,$uid,$context) = @_;
	$uid     = Siikir::Util::stripID($uid);
	$context = Siikir::Util::stripID($context);

	# User must exist.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "The user ID $uid wasn't found!";
		return undef;
	}

	# Fetch their blog configuration.
	if (!$self->Master->JsonDB->documentExists("blog/index/$uid")) {
		$@ = "No blog index information for ID $uid!";
		return {};
	}
	my $db = $self->Master->JsonDB->getDocument("blog/index/$uid");

	# Delete any private posts.
	if (defined $context) {
		if ($uid != $context && !$self->Master->User->isAdmin($context)) {
			my @keys = keys %{$db};
			foreach my $id (@keys) {
				if ($db->{$id}->{privacy} eq "private") {
					delete $db->{$id};
				}
			}
		}
	}

	return $db;
}

=head2 data getCategories (int uid)

Get the blog categories cache for the user. Returns a hashref in the format:

  {
    "category name" => {
      entry_id => friendly_id,
    },
  };

=cut

sub getCategories {
	my ($self,$uid) = @_;
	$uid = Siikir::Util::stripID($uid);

	# User must exist.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "The user ID $uid wasn't found!";
		return undef;
	}

	# Fetch their blog configuration.
	if (!$self->Master->JsonDB->documentExists("blog/tags/$uid")) {
		$@ = "No tags information for ID $uid!";
		return {};
	}
	my $db = $self->Master->JsonDB->getDocument("blog/tags/$uid");

	return $db;
}

=head2 (int,string) postEntry (int userid, hash options)

Publish a blog entry. Options include:

  int id:          optional ID number for the post (required when editing an existing one)
  string fid:      optional friendly ID for the post (for URLs)
  int time:        epoch time of the post
  aref categories: array of categories
  bool sticky:     the stickiness of the post
  bool comments:   allow commenting on the entry
  bool emoticons:  allow emoticon parsing on the entry
  string avatar:   avatar filename to use (blank = use user's display picture)
  string privacy:  privacy setting (public, private, members, friends)
  string subject
  string body

Returns the ID number of the post and the friendly ID. Returns undef on error.

=cut

sub postEntry {
	my ($self,$uid,%opts) = @_;
	$uid = Siikir::Util::stripID($uid);

	# User must exist.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "The user ID $uid wasn't found!";
		return undef;
	}

	# Fetch their blog configuration.
	my $index      = $self->getIndex($uid);      # Index cache
	my $categories = $self->getCategories($uid); # Categories cache
	if (!defined $index || !defined $categories) {
		$@ = "Can't get index or categories for uid $uid: $@";
		return undef;
	}

	# Editing an existing blog post?
	my $id = $opts{id} || $self->nextId($index);
	$id = Siikir::Util::stripID($id);

	# Get a unique friendly ID.
	my $fid = $opts{fid} || "";
	if (!length $fid) {
		# The default friendly ID = the subject.
		$fid = lc($opts{subject}) || "";
		$fid =~ s/[^A-Za-z0-9]/-/ig;
		$fid =~ s/\-+/-/g;
	}

	# Make sure the friendly ID is unique.
	if (length $fid) {
		my $test     = $fid;
		my $try      = 1;
		while (1) {
			print STDERR "Look for collision, try number: $try\n";
			my $collision = 0;

			# Reserved words.
			foreach my $res (qw(category)) {
				if ($fid eq $res) {
					print STDERR "Reserved word $fid -> $res\n";
					$collision = 1;
					last;
				}
			}
			if (!$collision) {
				foreach my $post (keys %{$index}) {
					# skip the same post, for updates
					next if $post == $id;

					if ($index->{$post}->{fid} eq $fid) {
						# Not unique.
						$try++;
						$test = $fid . "_" . $try;
						$collision = 1;
						print STDERR "Existing post ($post <=> $id) $index->{$post}->{fid}\n";
						last;
					}
				}
			}

			# Was there a collision?
			if ($collision) {
				next;
			}

			# Nope.
			last;
		}
		$fid = $test;
	}

	# Write the post.
	$self->Master->JsonDB->writeDocument("blog/entries/$uid/$id", {
		id         => $id,
		fid        => $fid,
		ip         => $opts{ip} || $ENV{REMOTE_ADDR},
		time       => $opts{time} || time(),
		categories => ref($opts{categories}) eq "ARRAY" ? $opts{categories} : [],
		sticky     => $opts{sticky} ? 1 : 0,
		comments   => $opts{comments} ? 1 : 0,
		emoticons  => $opts{emoticons} ? 1 : 0,
		avatar     => $opts{avatar} || "",
		privacy    => $opts{privacy} || "public",
		author     => $uid,
		subject    => $opts{subject} || "",
		body       => $opts{body} || "",
	});

	# Update the index and categories cache.
	$index->{$id} = {
		id         => $id,
		fid        => $fid,
		time       => $opts{time} || time(),
		categories => ref($opts{categories}) eq "ARRAY" ? $opts{categories} : [],
		sticky     => $opts{sticky} ? 1 : 0,
		author     => $uid,
		privacy    => $opts{privacy} || "public",
		subject    => $opts{subject} || "",
	};
	foreach my $cat (@{$opts{categories}}) {
		$categories->{$cat}->{$id} = $fid;
	}
	$self->Master->JsonDB->writeDocument("blog/index/$uid", $index);
	$self->Master->JsonDB->writeDocument("blog/tags/$uid", $categories);

	return wantarray ? ($id, $fid) : $id;
}

=head2 bool deleteEntry (int userid, int entryid)

Delete a blog entry.

=cut

sub deleteEntry {
	my ($self,$uid,$id) = @_;
	$uid = Siikir::Util::stripID($uid);
	$id  = Siikir::Util::stripID($id);

	# User must exist.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "The user ID $uid wasn't found!";
		return undef;
	}

	# Fetch their blog configuration.
	my $index      = $self->getIndex($uid);      # Index cache
	my $categories = $self->getCategories($uid); # Categories cache
	my $post       = $self->getEntry($uid,$id);  # Post
	if (!defined $index || !defined $categories) {
		$@ = "Can't get index or categories for uid $uid: $@";
		return undef;
	}

	# Delete the post.
	if (!defined $post) {
		$@ = "The post doesn't exist.";
		return undef;
	}

	$id     = Siikir::Util::stripID($post->{id});
	my $fid = $post->{fid};

	# Delete the post.
	$self->Master->JsonDB->deleteDocument("blog/entries/$uid/$id");

	# Update the index and categories cache.
	delete $index->{$id};
	foreach my $cat (keys %{$categories}) {
		delete $categories->{$cat}->{$id};
		if (scalar keys %{$categories->{$cat}} == 0) {
			# Delete empty categories.
			delete $categories->{$cat};
		}
	}
	$self->Master->JsonDB->writeDocument("blog/index/$uid", $index);
	$self->Master->JsonDB->writeDocument("blog/tags/$uid", $categories);

	return 1;
}

=head2 data getEntry (int userid, int entryid[, bool editmode])

Return the blog entry. Returns a hash with the same info as you give to postEntry.

If the C<editmode> param is sent, no post filters are done to the entry (i.e.
emoticons aren't rendered). This is for editing an existing post.

=cut

sub getEntry {
	my ($self,$uid,$id,$editmode) = @_;
	$uid = Siikir::Util::stripID($uid);
	$id  = Siikir::Util::stripID($id);

	# User must exist.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "The user ID $uid wasn't found!";
		return undef;
	}

	# Fetch their blog entry.
	if (!$self->Master->JsonDB->documentExists("blog/entries/$uid/$id")) {
		$@ = "Blog entry $id not found!";
		return undef;
	}
	my $db = $self->Master->JsonDB->getDocument("blog/entries/$uid/$id");

	# If no FID, set it to the ID.
	if (!length($db->{fid})) {
		$db->{fid} = $id;
	}

	# Render the emoticons.
	if ($db->{emoticons} && !$editmode) {
		$db->{body} = $self->Master->Emoticons->render($db->{body},
			theme => $self->{smilies},
		);
	}

	return $db;
}

=head2 int resolveId (int userid, string entryid[, index[, int context]])

Given either an ID number or a friendly ID, resolve the post ID. If the post
doesn't exist, it returns undef. If you already have the blog index, provide it
as the third parameter to skip the extra lookup.

=cut

sub resolveId {
	my ($self,$uid,$check,$index,$context) = @_;
	$uid = Siikir::Util::stripID($uid);

	# User must exist.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "The user ID $uid wasn't found!";
		return undef;
	}

	# Get their index?
	if (!defined $index) {
		$index = $self->getIndex($uid);
	}

	# No index?
	if (!defined $index) {
		return undef;
	}

	# Resolve the ID.
	if ($check =~ /^\d+$/) {
		# It's a number, see if it's in the index.
		if (exists $index->{$check}) {
			# Privacy settings.
			if (defined $context && $context != $uid && !$self->Master->User->isAdmin($context) && $index->{$check}->{privacy} eq "private") {
				return undef;
			}
			return $check;
		}
		else {
			$@ = "ID number $check not found in index.";
			return undef;
		}
	}
	else {
		# It's a friendly ID.
		foreach my $id (keys %{$index}) {
			if ($index->{$id}->{fid} eq $check) {
				# Privacy settings.
				if (defined $context && $context != $uid && !$self->Master->User->isAdmin($context) && $index->{$id}->{privacy} eq "private") {
					return undef;
				}
				return $id;
			}
		}
		$@ = "Friendly ID $check not found in index.";
		return undef;
	}
}

=head2 int nextId (index)

Given the blog index from C<getIndex()>, returns the next available post ID
number.

=cut

sub nextId {
	my ($self,$index) = @_;

	$self->debug("Getting next available blog ID number");
	my @sorted = sort { $a <=> $b } keys %{$index};
	if (scalar(@sorted) == 0) {
		return 1;
	}

	$self->debug("Highest post ID is: $sorted[-1]");
	return $sorted[-1] + 1;
}

1;
