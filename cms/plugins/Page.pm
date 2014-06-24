package Siikir::Plugin::Page 2012.0518;

use 5.14.0;
use strict;
use warnings;
use Template;
use Time::Format qw(time_format);
use URI::Escape;
use Siikir::Time;

use base "Siikir::Plugin";

=head1 NAME

Siikir::Plugin::Page - Web page handling functions.

=cut

sub init {
	my $self = shift;

	$self->debug("Page plugin loaded!");

	# Required plugins.
	$self->requires(qw(
		CGI
		Session
		User
		Profile
		Messaging
		Mobile
		Traffic
	));

	# Default options.
	$self->options (
		# Main website title
		title   => "Siikir",

		# Web document root over HTTP
		docroot => "/", # or e.g. "/mysite/",

		# The default time zone for the server.
		timezone => -28800, # Pacific time
	);
	$self->interface([
		{
			category => "Page Settings",
			fields   => [
				{ section => "Website Settings" },
				{
					name    => "title",
					label   => "Site Title",
					text    => "The main name of your site (appears in the title tag on pages).",
					type    => "text",
				},
				{
					name    => "docroot",
					label   => "HTTP Document Root",
					text    => "The document root where Siikir's index.cgi is located (example: /, or /mysite/). Must begin with a /.",
					type    => "text",
				},
				{
					name    => "timezone",
					label   => "Time Zone",
					text    => "The time zone of the web server.",
					type    => "timezone",
				},
			],
		},
	]);

	# The docroot must start & end with /'s.
	if ($self->{docroot} !~ /^\//) {
		$self->{docroot} = "/$self->{docroot}";
	}
	if ($self->{docroot} !~ /\/$/) {
		$self->{docroot} = "$self->{docroot}/";
	}
}

sub run {
	my $self = shift;

	# First, process the user's request data.
	my $request = $self->processRequest();

	# Default TT vars.
	my $vars = $self->setVars($request);

	# Log traffic stats.
	$vars = $self->Master->Traffic->logTraffic($vars);

	# Process the TT.
	my $output = $self->processTT($request,$vars);
	$output //= ""; # Undefined is blank.

	# Save changes to their session.
	$self->Master->Session->commit();

	$self->Master->CGI->printHeaders();
	if ($output =~ /\$runtime\$/ && $::TIME_START) {
		my $runtime = time() - $::TIME_START;
		$output =~ s/\$runtime\$/$runtime/g;
	}
	print $output;
}

sub processTT {
	my ($self,$request,$vars) = @_;

	# Was there a controller?
	if (defined $request->{controller}) {
		$self->debug("Our controller: $request->{controller}");

		# Process it.
		my $ns = $request->{controller};
		$ns =~ s/\//::/g;
		$ns = $self->loadController($ns);

		# Run its code.
		no strict "refs";
		$vars = $ns->($self, $vars, $request->{extra});
	}

	# Did the controller call for a redirect?
	if ($self->Master->CGI->redirect()) {
		$self->Master->Session->commit();
		$self->Master->CGI->printHeaders();
		return;
	}

	# Ajax mode? Skip the templating if so.
	if (exists $vars->{param}->{ajax}) {
		return $self->to_json($vars);
	}

	# Layouts...
	my @layout = ();
	my $view   = $vars->{view};
	if (defined $vars->{layout}) {
		push (@layout, WRAPPER => "$self->{root}/layouts/$vars->{layout}.html");

		# If there's a version of the view with the specific layout attached, prefer that.
		if (-f "$self->{root}/pages/$vars->{view}-$vars->{layout}.html") {
			$view = $vars->{view} . "-" . $vars->{layout};
		}
	}

	# Process the Template.
	my $tt = Template->new({
		INCLUDE_PATH => [ "$self->{root}/pages", "$self->{root}/layouts", "$self->{root}/components" ],
		@layout,
		ENCODING     => "utf8",
		ABSOLUTE     => 1,
		RELATIVE     => 1,
	});

	my $output;
	$tt->process("$self->{root}/pages/$view.html", $vars, \$output) or $self->Master->fatal("Template error: $@");
	$output //= ""; # Undefined is blank, in case page redirects.

	# Post-process.
	$output = $self->postProcess($request,$vars,$output);

	return $output;
}

=head2 string loadController (string name)

Load a controller's code and return its full namespace. Here, the C<name> is the
controller's name, without the C<Siikir::Controller::> prefix. For example,
C<account::register> or C<profile::view>. If successful, returns the full namespace
name.

Example use:

  my $ns = $siikir->Page->loadController("account::register");
  $vars  = $ns->($self, $vars, $url);

=cut

sub loadController {
	my ($self,$name) = @_;

	# Construct the full namespace and the file name.
	my $ns = "Siikir::Controller::" . $name . "::process";
	my $file = $name;
	$file =~ s/::/\//g;
	($file) = ($file =~ /^(.+?)$/); # Detaint

	# Require the file.
	require "$self->{root}/pages/$file.pm";

	# Return it.
	return $ns;
}

=head2 hash setVars ()

Sets the initial Template Toolkit variables.

=cut

sub setVars {
	my ($self,$extra) = @_;

	my $vars = {
		sitename => $self->{title} || "Untitled Website",
		style    => "default", # 100% width panels, or custom = custom..
		layout   => "web",
		param    => $self->Master->CGI->params(),
		view     => "index",
		errors   => [],
		warnings => [],
		login    => $self->Master->Session->get("login") || 0,
		uid      => $self->Master->Session->get("uid") || 0,
		account  => {}, # End user's account info, if logged in
		unreadmsg => 0,
		isAdmin  => 0,
		cms      => {
			name    => "Siikir",
			version => $Siikir::VERSION,
		},
		env      => {
			# Select environment variables.
			REMOTE_ADDR => $ENV{REMOTE_ADDR},
			SERVER_ADDR => $ENV{SERVER_ADDR},
			SERVER_NAME => $ENV{SERVER_NAME},
		},
		constants => {},
	};

	# Untaint session params.
	if ($vars->{uid} =~ /^([0-9]+)$/) {
		$vars->{uid} = $1;
	}
	else {
		# Somehow invalid. Log them out!
		$vars->{uid}   = 0;
		$vars->{login} = 0;
	}

	# Generate the constants.
	my $year18 = (time_format("yyyy", time())) - 18;
	$vars->{constants}->{months} = [ qw(January February March April May June July August September October November December) ];
	$vars->{constants}->{mdays}  = [ 1..31 ];
	$vars->{constants}->{years}  = [ reverse(1900..$year18) ];
	$vars->{constants}->{timezones} = Siikir::Time::getTimezones(1);

	# Extra data to interpolate?
	if ($extra) {
		foreach my $key (keys %{$extra}) {
			$vars->{$key} = $extra->{$key};
		}
	}

	# Are they logged in?
	if ($vars->{login}) {
		# Get our account, local profile, admin status and unread messages.
		$vars->{account}            = $self->Master->User->getAccount($vars->{uid});

		# Was their account deleted on us?
		if ($vars->{account}->{level} eq "deleted") {
			# Don't continue. Forget the user.
			$self->Master->User->forget();
			$vars->{login} = 0;
			$vars->{uid}   = 0;
			$vars->{account} = {};
		}
		else {
			$vars->{account}->{profile} = $self->Master->Profile->getProfile($vars->{uid});
			$vars->{unreadmsg}          = $self->Master->Messaging->getUnread($vars->{uid});
			$vars->{isAdmin}            = $self->Master->User->isAdmin($vars->{uid});

			# If the admin, get the list of reported public photos.
			$vars->{notify}->{admin} = 0;
			if ($vars->{isAdmin}) {
				my $reports = $self->Master->Photo->getReports();
				$vars->{notify}->{admin} += scalar @{$reports};
			}
		}
	}

	# Are they mobile?
	if ($self->Master->Mobile->isMobile()) {
		# Get the mobile layout, ignore if it doesn't exist.
		my $layout = $self->Master->Mobile->layout();
		if (-f "$self->{root}/layouts/$layout.html") {
			$vars->{layout} = $layout;
			$vars->{mobile} = 1;
		}
	}

	return $vars;
}

=head2 vars showError (href vars, string error)

Utility function for pages who wish to show the user a fatal error: this kind of
error only wants to show an error message but not the page the user wanted. Example
is when a requested user is not found.

Usage is:

  # inside a controller....
  return $self->Master->Page->showError($vars, "That user ID was not found!");

=cut

sub showError {
	my ($self,$vars,$error) = @_;

	$vars->{errors} = [ $error ];
	$vars->{view}   = "fatal";

	return $vars;
}

=head2 data processRequest ()

Parse the user's request info. Returns a hash.

=cut

sub processRequest {
	my $self = shift;

	# First, format their request URI how we like it.
	my $uri = $ENV{REQUEST_URI};
	$uri =~ s/\?.*$//g; # Remove the query string
	$uri =~ s/^\/+//g;  # Remove preceeding /'s.
	$uri =~ s/\.\.//g;  # Remove double dots
	$uri = uri_unescape($uri);
	$self->debug("Request URI: $uri");

	# If the URI ends with a /, get rid of that!
	if ($uri =~ /\/$/) {
		$uri =~ s/\/+$//g;
		$self->debug("Request URI ended with /, redirect them to $uri");

		# An HTTP 301 redirect will sort it out!
		$self->Master->CGI->setHeader(
			status => "301 Moved Permanently",
			location => "/$uri",
		);
		$self->Master->CGI->printHeaders();
		exit(0);
	}

	# Resolve their request URI and find a view and/or controller.
	my $request = $self->resolveURI($uri);

	return $request;
}

=head2 data resolveURI (string URI[, array trimmed])

Resolve their (pre-formatted) request URI to find a view and/or controller
for the user. Returns a hashref with the keys "controller" and "view".
The controller may be undef but the view will at least be "404" if no page
was found.

This method will call itself recursively until the URI is exhausted or the
view or controller was found. When it calls recursively, the trimmed path
components will come in as the C<trimmed> array.

=cut

sub resolveURI {
	my ($self,$uri,@trimmed) = @_;

	# Controller and view.
	my ($c,$v) = (undef,undef);

	$self->debug("Resolve URI: $uri");

	# Shortcut to page root.
	my $pages = "$self->{root}/pages";

	# If we have a .html at this exact path, then great!
	if (-f "$pages/$uri.html" || -f "$pages/$uri.pm") {
		# One of them does!
		if (-f "$pages/$uri.html") {
			# Good! We have a view!
			$v = $uri;
		}

		# And a controller?
		if (-f "$pages/$uri.pm") {
			# Yes!
			$c = $uri;
		}
	}
	else {
		# It doesn't exist. Is there an autohandler?
		my $auto = "$uri/index";
		if (-f "$pages/$auto.html" || -f "$pages/$auto.pm") {
			# One of them does!
			if (-f "$pages/$auto.html") {
				$v = $auto;
			}
			if (-f "$pages/$auto.pm") {
				$c = $auto;
			}
		}
		else {
			# No dice. Recurse.
			my @parts = split(/\//, $uri);
			unshift(@trimmed, pop(@parts));
			$uri = join("/",@parts);
			$self->debug("Recurse for: $uri, @trimmed");

			# Did we just exhaust the URI?
			if (scalar(@parts) == 0) {
				# Give up.
				return {
					controller => $c,
					view       => 404,
					trimmed    => [ @trimmed ],
				};
			}

			return $self->resolveURI($uri, @trimmed);
		}
	}

	# Return what we found.
	return {
		controller => $c,
		view       => $v,
		extra      => [ @trimmed ],
	};
}

=head2 string postProcess (href request, href vars, string html)

Run post-processing on the page output to, among other things, process pages
including one another.

=cut

sub postProcess {
	my ($self,$request,$vars,$html) = @_;

	# Fix/obfuscate e-mail links.
	while ($html =~ /<a\s*href=\"mailto:([^\"]+?)\"\s*>([^<]+?)<\/a>/i) {
		my $email = $1;
		my $label = $2;
		$email =~ s/\@/+/ig;
		$email =~ tr/A-Za-z/N-ZA-Mn-za-m/;
		$label =~ s/\@/+/ig;
		$label =~ tr/A-Za-z/N-ZA-Mn-za-m/;
		my $newcode = "<a href=\"/webmail?to=$email\" class=\"cms-email\">$label</a>";

		$html =~ s/<a\s*href=\"mailto:([^\"]+?)\"\s*>([^<]+?)<\/a>/$newcode/i;
	}

	# Look for our custom include tags.
	while ($html =~ /<include>(.+?)<\/include>/i) {
		my $link = $1;
		$link =~ s/^\///g; # Remove preceding slashes.
		my $query = "";
		if ($link =~ /\?/) {
			($link,$query) = split(/\?/, $link, 2);
		}

		# Clone the vars.
		my $nrequest = $self->resolveURI("$link");
		my $nvars = $self->setVars($nrequest);

		$nvars->{view}   = $nrequest->{view};
		$nvars->{layout} = undef; # no layout since we're including
		$nvars->{param} = {};
		foreach my $pair (split(/\&/, $query)) {
			my ($what,$is) = split(/=/, $pair, 2);
			$nvars->{param}->{$what} = $is;
		}

		$self->debug("TT is INCLUDING another file: $link");
		my $output = $self->processTT($nrequest, $nvars);
		$html =~ s/<include>(.+?)<\/include>/$output/i;
	}

	# Handle <nofilter> first.
	my %nofilter = ();
	my $nofilter_i = 0;
	while ($html =~ /<nofilter>(.+?)<\/nofilter>/si) {
		$nofilter{$nofilter_i} = $1;
		$html =~ s/<nofilter>(.+?)<\/nofilter>/<filter-placeholder-$nofilter_i>/si;
		$nofilter_i++;
	}

	# Handle links.
	while ($html =~ /(['"])\$link:(.+?)['"]/i) {
		my $qq = $1;
		my $link = $2;
		my $query = undef;
		if ($link =~ /\?/) {
			($link,$query) = split(/\?/, $link, 2);
		}

		# Mod_rewrite?
		my $href = "/$link.html"; # TODO handle other URLs
		if (defined $query) {
			$href .= "?$query";
		}

		# Fix the & for W3C validation.
		$href =~ s/&/&amp;/g;

		# Filter it back in.
		$html =~ s/['"]\$link:(.+?)['"]/$qq$href$qq/si;
	}

	# A single "$link" means /. TODO make this not mean / all the time.
	$html =~ s/\$link/\//sig;

	# Filter back in the <nofilter>'s.
	$html =~ s/<filter-placeholder-(\d+)>/$nofilter{$1}/sig;

	# Return it.
	return $html;
}

=head2 string to_json (vars)

=cut

sub to_json {
	my ($self,$vars) = @_;

	# Trim down the vars so we don't give out too much information.
	my @hidden = qw(
		sitename
		cms
		controller
		view
		layout
		extra
		notify
		param
		traffic
		uid
		account
		env
		style
		login
		constants
		isAdmin
		unreadmsg
	);
	foreach my $h (@hidden) {
		delete $vars->{$h};
	}

	# JSON.
	$self->Master->CGI->setHeader(type => 'text/plain');

	require JSON;
	my $json = JSON->new->utf8->pretty;
	return $json->encode($vars);
}

1;
