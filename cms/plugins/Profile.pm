package Siikir::Plugin::Profile 2011.0930;

use 5.14.0;
use strict;
use warnings;

use base "Siikir::Plugin";

=head1 NAME

Siikir::Plugin::Profile - User profile management.

=cut

sub init {
	my $self = shift;

	$self->debug("Profile plugin loaded!");
	$self->requires("Search");

	# Options.
	$self->options (
		# List of profile fields.
		fields => [
			{
				category => "Basic Info",
				fields   => [
					{ section => "Your Name" },
					{
						name  => "first_name",
						label => "First Name",
						text  => "Your real first name.",
						type  => "text",
					},
					{
						name  => "last_name",
						label => "Last Name",
						text  => "Your real last name.",
						type  => "text",
					},
					{
						name  => "nickname",
						label => "Nickname",
						text  => "The name you'd prefer to go by on Siikir.",
						type  => "text",
					},

					{ section => "The Basics" },
					{
						name    => "gender",
						label   => "Gender",
						type    => "radio",
						options => [
							"male"   => "Male",
							"female" => "Female",
							""       => "Prefer not to say",
						],
					},
					{
						name    => "location",
						label   => "Location",
						text    => "Your location in your own words (ex. Los Angeles)",
						type    => "text",
					},
					{
						name    => "zipcode",
						label   => "Zip Code",
						text    => "Your zip code will help other users find you in searches.",
						type    => "number",
						minlength => 5,
						maxlength => 5,
					},
					{
						name    => "hometown",
						label   => "Hometown",
						text    => "Where you grew up.",
						type    => "text",
					},
					{
						name    => "profession",
						label   => "Profession",
						text    => "What do you do for a living?",
						type    => "text",
					},
					{
						name    => "hobbies",
						label   => "Hobbies",
						text    => "What do you do for fun?",
						type    => "text",
					},
				],
			},

			{
				category => "Appearance/Details",
				fields   => [
					{
						name    => "race",
						label   => "Race/Ethnicity",
						type    => "select",
						options => [
							"African American" => "African American",
							"African Origin"   => "African Origin",
							"American Indian"  => "American Indian",
							"Asian"            => "Asian",
							"Black"            => "Black",
							"Latin/Hispanic"   => "Latin/Hispanic",
							"Middle Eastern"   => "Middle Eastern",
							"Mixed Race"       => "Mixed Race",
							"Oriental"         => "Oriental",
							"South Asian"      => "South Asian",
							"White/European"   => "White/European",
							"Other"            => "Other",
							""                 => "Prefer not to say",
						],
					},
					{
						name    => "eyes",
						label   => "Eye Color",
						type    => "select",
						options => [
							"Black"  => "Black",
							"Blue"   => "Blue",
							"Brown"  => "Brown",
							"Gray"   => "Gray",
							"Green"  => "Green",
							"Hazel"  => "Hazel",
							"Purple" => "Purple",
							""       => "Prefer not to say",
						],
					},
					{
						name    => "hair",
						label   => "Hair Color",
						type    => "text",
					},
					{
						name    => "height",
						label   => "Height",
						type    => "height",
					},
					{
						name    => "weight",
						label   => "Weight",
						type    => "number-range",
						low     => 90,
						high    => 299,
						suffix  => " lbs",
					},
					{
						name    => "bodyhair",
						label   => "Body Hair",
						type    => "select",
						options => [
							"Smooth"         => "Smooth",
							"Shaved"         => "Shaved",
							"Slightly hairy" => "Slightly hairy",
							"Average"        => "Average",
							"Hairy"          => "Hairy",
							"Very hairy"     => "Very hairy",
							"Gorilla-like"   => "Gorilla-like",
							""               => "Prefer not to say",
						],
					},
					{
						name    => "bodytype",
						label   => "Body Type",
						type    => "select",
						options => [
							"Athletic"     => "Athletic",
							"Average"      => "Average",
							"Body builder" => "Body builder",
							"Little extra" => "Little extra",
							"More to love" => "More to love",
							"Slim/Slender" => "Slim/Slender",
							""             => "Prefer not to say",
						],
					},
					{
						name    => "smoke",
						label   => "Smoke?",
						type    => "radio",
						options => [
							"Yes" => "Yes",
							"No"  => "No",
							""    => "Prefer not to say",
						],
					},
					{
						name    => "drink",
						label   => "Drink?",
						type    => "radio",
						options => [
							"Yes"       => "Yes",
							"No"        => "No",
							"Sometimes" => "Sometimes",
							"Socially"  => "Socially",
							"Rarely"    => "Rarely",
							""          => "Prefer not to say",
						],
					},
					{
						name    => "politics",
						label   => "Politics",
						type    => "text",
					},
					{
						name    => "religion",
						label   => "Religion",
						type    => "text",
					},
					{
						name    => "orientation",
						label   => "Sexual Orientation",
						type    => "checkgroup",
						options => [
							"Straight" => "Straight",
							"Bi"       => "Bi",
							"Gay"      => "Gay",
							"Lesbian"  => "Lesbian",
							"Curious"  => "Curious",
							"Transgendered" => "Transgendered",
							"Confused" => "Confused",
							"Not sure" => "Not sure",
						],
					},
					{
						name    => "dating",
						label   => "Marital Status",
						type    => "select",
						options => [
							"Single"              => "Single",
							"Single, looking"     => "Single, looking",
							"Single, not looking" => "Single, not looking",
							"Dating"              => "Dating",
							"In a relationship"   => "In a relationship",
							"Confused"            => "Confused",
							"Swinger"             => "Swinger",
							"Married"             => "Married",
							"Divorced"            => "Divorced",
							"Widowed"             => "Widowed",
							""                    => "Prefer not to say",
						],
					},
				],
			},
			{
				category => "Interests/Essays",
				fields   => [
					{
						name    => "whatever",
						label   => "Whatever I Want",
						text    => "This space is free for you to speak your mind.",
						type    => "essay",
					},
					{
						name    => "about",
						label   => "About Me",
						text    => "What makes you, you?",
						type    => "essay",
					},
					{ section => "Favorite Things" },
					{
						name    => "music",
						label   => "Favorite Music",
						type    => "essay",
					},
					{
						name    => "movies",
						label   => "Favorite Movies",
						type    => "essay",
					},
					{
						name    => "books",
						label   => "Favorite Books",
						type    => "essay",
					},
					{
						name    => "quotes",
						label   => "Favorite Quotes",
						type    => "essay",
					},
				],
			},
			{
				category => "Contact Info",
				fields   => [
					{
						name   => "aim",
						icon   => "aim",
						label  => "AOL Instant Messenger",
						text   => "Your AIM screen name.",
						type   => "text",
					},
					{
						name   => "msn",
						icon   => "msn",
						label  => "MSN/Windows Live Messenger",
						text   => "The e-mail address you use with Windows Live Messenger.",
						type   => "text",
					},
					{
						name   => "yahoo",
						icon   => "yahoo",
						label  => "Yahoo! Messenger",
						text   => "Your Yahoo! ID.",
						type   => "text",
					},
					{
						name   => "xmpp",
						icon   => "xmpp",
						label  => "Google Talk/Jabber/XMPP ID",
						type   => "text",
					},
					{
						name   => "website",
						icon   => "www",
						label  => "Personal Website URL",
						type   => "text",
					},
					{
						name   => "email",
						icon   => "email",
						label  => "Private E-mail Address",
						text   => "This is not displayed on your profile. It is used to send you "
							. "notifications and help recover lost passwords.",
						type   => "text",
					},
				],
			},
			{
				category => "Site Settings",
				fields   => [
					{
						name    => "privacy",
						label   => "Privacy Settings",
						text    => "Configure your optional privacy settings (<a href=\"/help/privacy\" target=\"_blank\">Read more about privacy settings</a>).",
						type    => "checkgroup",
						options => [
							"unlinkable" => "<strong>Unlinkable:</strong> Don't allow my profile to be bookmarked or linked to.",
						],
					},
					{
						name   => "display",
						label  => "Display Settings",
						text   => "Configure your optional site display settings.",
						type   => "checkgroup",
						options => [
							"showadult" => "Automatically show adult photos without making me click them first.",
						],
					},
					{
						name    => "geoapi",
						label   => "Use HTML 5 Geolocation API",
						text    => "If you enable this option, and if your browser supports Geolocation, Siikir will ask "
							. "you for permission to get your physical location (it's not as accurate as GPS, but it may "
							. "be helpful for users outside the US who can't use a zipcode to provide their location).",
						type    => "checkgroup",
						options => [
							"true" => "Use my browser's Geolocation API",
						],
					},
					{
						name   => "timezone",
						label  => "Time Zone",
						text   => "Setting your time zone will help Siikir.com show dates and times in your local time zone.",
						type   => "timezone",
					},
				],
			},
		],
	);
}

=head1 METHODS

=head2 aref fields ()

Retrieve the full data structure for the profile fields.

=cut

sub fields {
	my $self = shift;
	return $self->{fields};
}

=head2 bool setFields (int uid, href fields)

Set one or multiple profile fields for the user C<uid>.

Special note: if one of the given fields is "zipcode", the latitude and longitude
of the zipcode will be looked up and stored as "zip-latitude" and "zip-longitude".

=cut

sub setFields {
	my ($self,$uid,$fields) = @_;
	$uid = Siikir::Util::stripID($uid);

	# User exists?
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "User ID $uid not found!";
		return undef;
	}

	# Do they have a DB?
	my $db = {};
	if ($self->Master->JsonDB->documentExists("profile/$uid")) {
		$db = $self->Master->JsonDB->getDocument("profile/$uid");
	}

	# If they don't have a location and we find it via a zip lookup, set it.
	my $zipLocation = "";

	# If they change something crucial to their search result, flag if we
	# need to rebuild the cache.
	my $rebuildSearch = 0;

	# Commit all params.
	foreach my $key (keys %{$fields}) {
		$db->{$key} = $fields->{$key};

		# The zipcode?
		if ($key eq "zipcode") {
			my $data = Siikir::Util::getZipcode($fields->{$key});
			if (defined $data) {
				$db->{'zip-latitude'}  = $data->{latitude};
				$db->{'zip-longitude'} = $data->{longitude};
				$zipLocation = "$data->{city}, $data->{state}";
				$rebuildSearch = 1;
			}
			else {
				delete $db->{'zip-latitude'};
				delete $db->{'zip-longitude'};
				$rebuildSearch = 1;
			}
		}
		elsif ($key =~ /^(nickname|first_name|gender|orientation)$/i) {
			# This data is shown on search results.
			$rebuildSearch = 1;
		}
	}

	# No location?
	if (!exists $db->{location} || length($db->{location}) == 0) {
		$db->{location} = $zipLocation;
	}

	# Save the DB.
	$self->Master->JsonDB->writeDocument("profile/$uid", $db);

	# Need to rebuild the search cache?
	if ($rebuildSearch) {
		$self->Master->Search->buildCache();
	}

	return 1;
}

=head2 data getProfile (int uid || string username)

Retrieve a user's profile. Returns undef if the user doesn't exist, or an
empty hashref if the user's profile is empty.

Of special note: the returned data will contain the following keys which
can't be profile keys and would override them if they exist:

  displayname: The user's displayed name.
  username:    The user's username.
  userid:      The user's user ID
  age:         The user's calculated age
  admin:       Whether the user is an admin

The display name is resolved by the following in order:

  User's nickname
  User's first_name
  User's ID, ucfirst

=cut

sub getProfile {
	my ($self,$uid) = @_;

	# Did they give us a username?
	$uid = $self->Master->User->getId($uid);
	$uid = Siikir::Util::stripID($uid);

	return undef unless defined $uid;

	# User exists?
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "User ID $uid not found!";
		return undef;
	}

	# Do they have a DB?
	my $db = {};
	if ($self->Master->JsonDB->documentExists("profile/$uid")) {
		$db = $self->Master->JsonDB->getDocument("profile/$uid");
	}

	# Get their DOB from their account.
	my $acct = $self->Master->User->getAccount($uid);
	return undef if $acct->{level} eq "deleted"; # Deleted accounts = undef profile.

	# Inject special keys.
	$db->{username}    = $self->Master->User->getUsername($uid);
	$db->{displayname} = $db->{nickname} || $db->{first_name} || ucfirst($db->{username});
	$db->{userid}      = $uid;
	$db->{age}         = Siikir::Util::getAge($acct->{dob});
	$db->{admin}       = $self->Master->User->isAdmin($uid);

	return $db;
}

1;
