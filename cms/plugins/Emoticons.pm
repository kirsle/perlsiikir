package Siikir::Plugin::Emoticons 2011.0930;

use 5.14.0;
use strict;
use warnings;
use JSON;

use base "Siikir::Plugin";

=head1 NAME

Siikir::Plugin::Emoticons - Centralized emoticon rendering.

=cut

sub init {
	my $self = shift;

	$self->debug("Emoticons plugin loaded!");

	# Keep internal cache of emoticon sets.
	$self->{_cache} = {};

	# Options.
	$self->options (
		# Base directory via HTTP where emoticon themes are kept
		http => "/static/smileys",

		# Base directory via filesystem
		private => "./static/smileys",

		# Default smiley theme
		default => "tango",
	);

	# Interface.
	$self->interface ([
		{
			category => "Emoticon Settings",
			fields   => [
				{
					name  => "http",
					label => "HTTP Base Directory",
					text  => "Base directory of emoticon themes, over HTTP (i.e. /static/smileys)",
					type  => "text",
				},
				{
					name  => "private",
					label => "Local Base Directory",
					text  => "Path to emoticon sets relative to the server (e.g. ./static/smileys)",
					type  => "text",
				},
				{
					name  => "default",
					label => "Default Smiley Theme",
					text  => "Should exist under the base directory above.",
					type  => "text",
				},
			],
		},
	]);
}

=head1 METHODS

=head2 string http ()

Get the HTTP path to the smiley themes.

=cut

sub http {
	my $self = shift;
	return $self->{http};
}

=head2 string render(string[, options])

Render emoticons in the given string. Options include:

  theme: Optional theme to use (if not found, the default is used).

=cut

sub render {
	my ($self, $string, %opts) = @_;

	# Theme.
	my $theme = exists $opts{theme} ? $opts{theme} : $self->{default};

	# Load the theme.
	my $smileys = $self->loadTheme($theme);
	if (!defined $smileys) {
		die "$@";
	}

	# Process all smileys.
	foreach my $img (sort keys %{$smileys->{map}}) {
		foreach my $trigger (@{$smileys->{map}->{$img}}) {
			if ($string =~ /\Q$trigger\E/) {
				# Substitute it.
				my $sub = "<img src=\"$self->{http}/$smileys->{theme}/$img\" alt=\"$trigger\" title=\"$trigger\">";
				$string =~ s/([^A-Za-z0-9:\-]|^)\Q$trigger\E([^A-Za-z0-9:\-]|$)/$1$sub$2/g;
			}
		}
	}

	return $string;
}

=head2 href loadTheme (string theme)

Pre-load and cache the theme configuration. Returns the parsed JSON from the
emoticons.json file from the theme, which should look like this:

  {
    name => "Theme Name",
	theme => "real theme name", # overrides given theme, in case default needs to be used
    map  => {
      "smile.png" => [ ":-)", ":)", ":smile:" ],
      ...
    },
  }

=cut

sub loadTheme {
	my ($self,$theme) = @_;

	# Cached?
	if ($self->{_cache}->{$theme}) {
		return $self->{_cache}->{$theme};
	}

	# Only if the theme file exists.
	if (!-f "$self->{private}/$theme/emoticons.json") {
		$@ = "Failed to load theme $theme: trying default instead.";
		if (-f "$self->{private}/$self->{default}/emoticons.json") {
			$theme = $self->{default};
		}
		else {
			$@ = "Failed to load theme $theme and the default theme $self->{default} wasn't found either.";
			return undef;
		}
	}

	# Read it.
	open (JSON, "$self->{private}/$theme/emoticons.json");
	local $/;
	my $json = <JSON>;
	close (JSON);

	# Parse.
	my $data   = {};
	eval {
		$data = decode_json($json);
	};
	if ($@) {
		# Make it fatal.
		die "JSON parse fail for emoticon theme $theme: $@";
	}

	# Cache it.
	$data->{theme} = $theme;
	$self->{_cache}->{$theme} = $data;

	# Return it.
	return $data;
}

1;
