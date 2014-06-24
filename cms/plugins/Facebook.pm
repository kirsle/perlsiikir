package Siikir::Plugin::Facebook 2011.0930;

use 5.14.0;
use strict;
use warnings;
use Siikir::Util;
use URI::Escape;
use Digest::MD5 qw(md5_hex);

use base "Siikir::Plugin";

=head1 NAME

Siikir::Plugin::Facebook - Integration with Facebook Graph.

=cut

sub init {
	my $self = shift;

	$self->debug("Facebook plugin loaded!");
	$self->requires(qw(User CGI JsonDB));

	# Options.
	$self->options(
		fb_api_key  => '',
		fb_app_id   => '',
		fb_secret   => '',
	);
	$self->interface([
		{
			category => "Facebook Options",
			fields   => [
				{ section => "Facebook Graph Settings" },
				{
					name  => "fb_api_key",
					label => "Facebook API Key",
					type  => "text",
				},
				{
					name  => "fb_app_id",
					label => "Facebook App ID",
					type  => "text",
				},
				{
					name  => "fb_secret",
					label => "Facebook App Secret",
					type  => "text",
				},
			],
		},
	]);
}

=head1 METHODS

=head2 bool configured ()

Quick way to determine whether Facebook Connect has been fully configured.

=cut

sub configured {
	my $self = shift;

	if (length $self->{fb_api_key} && length $self->{fb_app_id} && length $self->{fb_secret}) {
		return 1;
	}

	return undef;
}

=head2 href appinfo ()

If the plugin is configured with Facebook Graph settings, this method returns
a hash containing the keys "app_id" and "secret" for the app. Else, this method
returns undef.

=cut

sub appinfo {
	my $self = shift;

	if ($self->configured()) {
		return {
			api_key => $self->{fb_api_key},
			app_id  => $self->{fb_app_id},
			secret  => $self->{fb_secret},
		};
	}

	return undef;
}

=head2 string getLoginURL ()

Generates a Facebook login URL. The pingback URL will be set to:

  http://{SERVER_NAME}/account/FacebookConnect

Returns C<undef> if the Facebook app info hasn't been configured.

=cut

sub getLoginURL {
	my $self = shift;

	# Get the app info.
	my $app = $self->appinfo();

	# No app info = no URL.
	if (!defined $app) {
		return undef;
	}

	# Pingback URL.
	my $ping = uri_escape("http://$ENV{SERVER_NAME}/account/FacebookConnect?connect=1&ReturnUrl="
		. uri_escape("http://$ENV{SERVER_NAME}/account/FacebookConnect?returning=1"));

	# Generate the URL.
	my $url = sprintf "https://www.facebook.com/login.php?"
		. "api_key=%s&"
		. "extern=1&"
		. "fbconnect=1&"
		. "req_perms=email&"
		. "return_session=1&"
		. "v=1.0&"
		. "next=%s&"
		. "fb_connect=1&"
		. "cancel_url=%s",
		$app->{api_key},
		$ping,
		$ping;

	return $url;
}

=head2 int checkLogin ()

After Facebook Connect sends the redirect back to /account/FacebookConnect, this
method will attempt to log in the user.

Returns 1 on valid login, 0 when no user is associated to this FB account, or
undef on error (and sets $@).

=cut

sub checkLogin {
	my $self = shift;

	# Get the FB cookies.
	my $cookie = $self->parseCookies();

	# Verified cookies?
	if ($cookie->{verified}) {
		# Good! Look up a user who has this Facebook account.
		my $user = $cookie->{user};
		if ($self->Master->JsonDB->documentExists("users/by-facebook/$user")) {
			# Read it.
			my $db = $self->Master->JsonDB->getDocument("users/by-facebook/$user");

			# Get the user ID.
			my $uid = $db->{id};

			# Become this user.
			$self->Master->User->become($uid);
			return 1;
		}
		else {
			return 0;
		}
	}

	$@ = "Facebook cookie verification failed.";
	return undef;
}

=head2 href parseCookies ()

After a successful Facebook login, this method parses the FB cookies and returns
them. It returns undef if something went wrong.

Cookie names returned:

  int user
  str session_key
  int expires
  str ss

=cut

sub parseCookies {
	my $self = shift;

	# Only bother if configured.
	if (!$self->configured()) {
		return undef;
	}

	# Get the app info.
	my $app = $self->appinfo();

	# Parse the cookies.
	my $result = {};
	my $cookies = $self->Master->CGI->getCookies();
	foreach my $name (keys %{$cookies}) {
		if ($name =~ /^$app->{api_key}_(.+?)$/i) {
			$result->{$1} = $cookies->{$name};
		}
	}

	# Authenticate this.
	my $signature = "";
	foreach my $key (qw(expires session_key ss user)) {
		$signature .= join("=", $key, $result->{$key});
	}
	$signature .= $app->{secret};
	my $hash = md5_hex($signature);

	# If our computed hash matches the one given by Facebook, we're good to go.
	if ($hash eq $cookies->{ $app->{api_key} }) {
		$result->{verified} = 1;
	}
	else {
		$result->{verified} = 0;
	}

	return $result;
}

=head2 bool createLink (int userid, int facebookid)

Creates a link between a Facebook ID and a Siikir User ID. This is done during
registration after the user is created via Facebook Connect.

=cut

sub createLink {
	my ($self, $uid, $fbid) = @_;
	$uid = Siikir::Util::stripID($uid);
	$fbid = Siikir::Util::stripSimple($fbid);

	# Valid FB ID?
	if ($fbid !~ /^\d+$/) {
		$@ = "Invalid formatted Facebook ID!";
		return undef;
	}

	# User must exist.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "User ID $uid not found!";
		return undef;
	}

	# Get the account.
	my $acct = $self->Master->User->getAccount($uid);
	$acct->{facebook} = $fbid;
	$self->Master->User->setAccount($uid, $acct);

	# Create the link.
	$self->Master->JsonDB->writeDocument("users/by-facebook/$fbid", {
		id => $uid,
	});

	return 1;
}

=head2 bool removeLink (int userid)

Remove a Facebook Connect link.

=cut

sub removeLink {
	my ($self,$uid) = @_;
	$uid = Siikir::Util::stripID($uid);

	# User must exist.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "User ID $uid not found!";
		return undef;
	}

	# Get the account.
	my $acct = $self->Master->User->getAccount($uid);

	# Is there an FB account?
	if (exists $acct->{facebook} && length $acct->{facebook}) {
		my $fbid = delete $acct->{facebook};

		# Delete the link.
		$self->Master->JsonDB->deleteDocument("users/by-facebook/$fbid");
		$self->Master->User->setAccount($uid, $acct);
	}

	return 1;
}

1;
