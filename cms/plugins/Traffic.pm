package Siikir::Plugin::Traffic 2012.1114;

use 5.14.0;
use strict;
use warnings;
use Siikir::Time;

use base "Siikir::Plugin";

=head1 NAME

Siikir::Plugin::Traffic - Simple traffic logging.

=cut

sub init {
	my $self = shift;

	# Needs JsonDB.
	$self->requires("JsonDB");
	$self->requires("CGI");

	# Options.
	$self->options (
		cookie => "SiikirTraffic",
	);

	$self->interface ([
		{
			category => "Traffic Settings",
			fields   => [
				{
					name  => "cookie",
					label => "HTTP Cookie Name",
					text  => "The name of the HTTP cookie to use to track visitors.",
					type  => "text",
				},
			],
		},
	]);
}

=head1 METHODS

=head2 vars logTraffic (href vars)

Starts the automatic traffic logging. Takes and returns a Template Toolkit
vars hash.

=cut

sub logTraffic {
	my ($self,$vars) = @_;
	$self->debug("logTraffic called");

	# Don't do this multiple times per request.
	if (exists $vars->{traffic}) {
		$self->debug("Traffic already logged in this request!");
		return $vars;
	}

	# Get their cookie first if they have one. The cookie value will either
	# be their original HTTP referrer (if exists and valid), or else a 1.
	my $cookie = $self->Master->CGI->getCookie($self->{cookie});
	my $addr   = $ENV{REMOTE_ADDR};
	if (exists $ENV{X_FORWARDED_FOR} && $ENV{X_FORWARDED_FOR} =~ /^[0-9\.\:]$/) {
		$addr = "$ENV{X_FORWARDED_FOR} (via proxy $ENV{REMOTE_ADDR})";
	}

	# Log hit counts first. We need four kinds:
	#  - Unique today      - Unique total
	#  - Hits today        - Hits total
	my $today    = Siikir::Time::getTimestamp("yyyy-mm-dd");
	my %hitfiles = (
		"unique/$today" => "unique_today",
		"unique/total"  => "unique_total",
		"hits/$today"   => "hits_today",
		"hits/total"    => "hits_total",
	);
	if (!defined $cookie) {
		# No cookie defined = we add to the hit files.
		foreach my $file (keys %hitfiles) {
			if ($file =~ /^hits/) {
				# Hit file is just a simple counter.
				my $db = { hits => 0 };
				if ($self->Master->JsonDB->documentExists("traffic/$file")) {
					$db = $self->Master->JsonDB->getDocument("traffic/$file");
				}
				$db->{hits}++;
				$self->Master->JsonDB->writeDocument("traffic/$file", $db);

				# Store the copy.
				$vars->{traffic}->{ $hitfiles{$file} } = $db->{hits};
			}
			else {
				# Unique file is a collection of IP addresses.
				my $db = {};
				if ($self->Master->JsonDB->documentExists("traffic/$file")) {
					$db = $self->Master->JsonDB->getDocument("traffic/$file");
				}
				
				# Exists?
				if (!exists $db->{$addr}) {
					$db->{$addr} = time();
					$self->Master->JsonDB->writeDocument("traffic/$file", $db);
				}

				# Store the copy.
				$vars->{traffic}->{ $hitfiles{$file} } = scalar keys %{$db};
			}
		}
	}
	else {
		# We still want to know the current stats.
		foreach my $file (keys %hitfiles) {
			if ($file =~ /^hits/) {
				# Hit file is just a simple counter.
				my $db = { hits => 0 };
				if ($self->Master->JsonDB->documentExists("traffic/$file")) {
					$db = $self->Master->JsonDB->getDocument("traffic/$file");
				}

				# Store the copy.
				$vars->{traffic}->{ $hitfiles{$file} } = $db->{hits};
			}
			else {
				# Unique file is a collection of IP addresses.
				my $db = {};
				if ($self->Master->JsonDB->documentExists("traffic/$file")) {
					$db = $self->Master->JsonDB->getDocument("traffic/$file");
				}
				
				# Store the copy.
				$vars->{traffic}->{ $hitfiles{$file} } = scalar keys %{$db};
			}
		}
	}

	# Log the HTTP referrer.
	my $referer = 1;
	if (exists $ENV{HTTP_REFERER} && length $ENV{HTTP_REFERER}) {
		# Branch and check this.
		my $referer = $self->logReferer($ENV{HTTP_REFERER});
		if (!defined $referer) {
			# Not a valid referer.
			$referer = 1;
		}
	}
	if (!defined $cookie) {
		$cookie = $referer;
		$self->Master->CGI->setCookie (
			-name  => $self->{cookie},
			-value => $cookie,
		);
	}

	return $vars;
}

=head2 string logReferer (string referer)

Handles the HTTP referrer and makes sure its valid (i.e. not the same domain,
and the page does reference the domain on it somewhere). If found invalid,
returns undefined.

=cut

sub logReferer {
	my ($self, $link) = @_;

	# Ignore if same domain.
	if ($link =~ /^(http|https|ftp):\/\/\Q$ENV{SERVER_NAME}\E/i) {
		return undef;
	}

	# Make a user agent.
	my $ua = new LWP::UserAgent();
	$ua->agent("Mozilla/4.0 (Compatible; MSIE 9.0)");
	$ua->max_size(1024*1024*2); # Only accept 2 MB size pages

	# See if the URL really links back to us.
	my $linksback = 0;
	my $reply = $ua->get($link);
	if ($reply->is_success) {
		if ($reply->content =~ /\Q$ENV{SERVER_NAME}\E/i) {
			$linksback = 1;
		}
	}

	# Does it?
	if ($linksback) {
		# Log it.
		my $db = [];
		eval {
			if ($self->Master->JsonDB->documentExists("traffic/referers")) {
				# Don't cache the result -- this list can get huge!
				$db = $self->Master->JsonDB->getDocument("traffic/referers", "no_cache");
			}
		};

		push (@{$db}, $link);

		$self->Master->JsonDB->writeDocument("traffic/referers", $db);
		return $link;
	}

	return undef;
}

=head2 href getDetails ()

Returns a hash of details about hits/unique visitors. Returns a hash in the
format:

  {
    traffic => [
      {
        date => '2011-12-05',
        hits => 30,
        unique => 12,
      },
    ],
    most_unique => [ '2011-12-05', 12 ],
    most_hits   => [ '2011-12-05', 30 ],
	oldest      => '2011-12-05',
  }

=cut

sub getDetails {
	my $self = shift;

	my $return = {
		traffic     => [],
		most_unique => [ '0000-00-00', 0 ],
		most_hits   => [ '0000-00-00', 0 ],
		oldest      => '',
	};

	# List all documents.
	my @hits = $self->Master->JsonDB->listDocuments("traffic/hits");

	foreach my $date (sort { $a cmp $b } @hits) {
		next if $date eq "total";
		$return->{oldest} = $date unless length $return->{oldest};
		my $hits_db = $self->Master->JsonDB->getDocument("traffic/hits/$date");
		my $uniq_db = $self->Master->JsonDB->getDocument("traffic/unique/$date");

		# Most we've seen?
		if ($hits_db->{hits} > $return->{most_hits}->[1]) {
			$return->{most_hits} = [ $date, $hits_db->{hits} ];
		}
		if (scalar keys %{$uniq_db} > $return->{most_unique}->[1]) {
			$return->{most_unique} = [ $date, scalar keys %{$uniq_db} ];
		}

		push (@{$return->{traffic}}, {
			date   => $date,
			hits   => $hits_db->{hits},
			unique => scalar keys %{$uniq_db},
		});
	}

	return $return;
}

=head2 aref getReferers (int recent=25)

Retrieve the referrer details. Returns a list in this format:

  {
    referers => [
      [ "http://...", 20 ], # pre-sorted by number of hits
    ],
	recent => [ recent list ]
  }

You can specify how many items should go in the "recent" list.

=cut

sub getReferers {
	my $self = shift;
	my $recent = shift || 25;

	my $db = [];
	if ($self->Master->JsonDB->documentExists("traffic/referers")) {
		$db = $self->Master->JsonDB->getDocument("traffic/referers", "no_cache");
	}

	# Count the links.
	my %unique = ();
	foreach my $link (@{$db}) {
		if (!exists $unique{$link}) {
			$unique{$link} = 1;
		}
		else {
			$unique{$link}++;
		}
	}

	# Sort them by popularity.
	my $return = {
		referers => [],
		recent   => [],
	};

	my @sorted = sort { $unique{$b} <=> $unique{$a} } keys %unique;
	foreach my $link (@sorted) {
		push (@{$return->{referers}}, [ $link, $unique{$link} ]);
	}

	for (my $i = -1; $i > (0 - $recent) && defined $db->[$i]; $i--) {
		push (@{$return->{recent}}, $db->[$i]);
	}

	return $return;
}

1;
