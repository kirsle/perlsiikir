package Siikir::Plugin::CGI 2011.0723;

use 5.14.0;
use strict;
use warnings;
use CGI;

use base "Siikir::Plugin";

=head1 NAME

Siikir::Plugin::CGI - Common CGI methods.

=cut

sub init {
	my $self = shift;

	$self->debug("CGI plugin loaded!");

	# Initialize CGI.
	if (defined $self->Master->{cgi}) {
		$self->{cgi} = $self->Master->{cgi};
	}
	else {
		$self->{cgi} = CGI->new();
	}

	# Eventual HTTP headers to send.
	$self->{headers} = {
		status   => 200,
		type     => "text/html",
		charset  => "UTF-8",
		location => undef,
		cookies  => [],
	};

	# Collect ALL parameters.
	if ($ENV{REQUEST_METHOD} eq "POST") {
		foreach my $what ($self->{cgi}->url_param()) {
			my @is = $self->{cgi}->url_param($what);
			if (scalar(@is) == 1) {
				$self->{param}->{$what} = scalar($is[0]);
			}
			else {
				$self->{param}->{$what} = [ @is ];
			}
		}
	}
	foreach my $what ($self->{cgi}->param()) {
		my @is = $self->{cgi}->param($what);
		if (scalar(@is) == 1) {
			$self->{param}->{$what} = scalar($is[0]);
		}
		else {
			$self->{param}->{$what} = [ @is ];
		}
	}

	# UTF8 decode all params.
	$self->{param} = Siikir::Util::utf8_decode($self->{param});
}

=head1 METHODS

=head2 CGI q()

Returns the CGI object directly.

=cut

sub q {
	my $self = shift;
	return $self->{cgi};
}

=head2 hash params ()

Get ALL CGI params.

=cut

sub params {
	my $self = shift;
	return $self->{param};
}

=head2 filehandle upload (string name)

Alias to CGI's upload().

=cut

sub upload {
	my $self = shift;
	return $self->{cgi}->upload(@_);
}

=head2 href getCookies ()

Get all the cookies.

=cut

sub getCookies {
	my $self = shift;

	my $cookies = {};
	foreach my $cookie ($self->{cgi}->cookie()) {
		$cookies->{$cookie} = $self->{cgi}->cookie(-name => $cookie);
	}

	return $cookies;
}

=head2 data getCookie (String name)

Get the cookie data from the cookie C<name>. Returns undef if there is no
such cookie there.

=cut

sub getCookie {
	my ($self,$name) = @_;
	return $self->{cgi}->cookie(-name => $name);
}

=head2 void setCookie (hash options)

Add a cookie to be sent with the HTTP headers. Use the standard CGI cookie
options, i.e.:

  -name
  -value
  -expires
  -domain

=cut

sub setCookie {
	my ($self, %opts) = @_;

	my $cookie = $self->{cgi}->cookie(%opts);
	push (@{$self->{headers}->{cookies}}, $cookie);
}

=head2 void setHeader (hash options)

Set one or more HTTP header options. Valid options:

  status
  type
  cookies  (WARNING: full arrayref of all cookies, be careful!)
  location

Don't change the cookies, use setCookie instead.

=cut

sub setHeader {
	my ($self, %opts) = @_;

	foreach my $key (keys %opts) {
		$self->{headers}->{$key} = $opts{$key};
	}
}

=head2 string redirect (string url)

Send an HTTP redirect action to the browser. If no URL is provided,
returns the current value of the location header (this is so the Page
plugin can print the headers and quit instead of invoking TT).

=cut

sub redirect {
	my ($self,$url) = @_;
	if (defined $url) {
		$self->{headers}->{status}   = "302 Found";
		$self->{headers}->{location} = $url;
	}
	return $self->{headers}->{location};
}

=head2 void printHeaders ()

Prints all the pending HTTP headers to the browser.

=cut

sub printHeaders {
	my $self = shift;

	my @headers = (
		-status  => $self->{headers}->{status},
		-type    => $self->{headers}->{type},
		-charset => $self->{headers}->{charset},
	);
	if (scalar @{$self->{headers}->{cookies}}) {
		push (@headers, -cookie => $self->{headers}->{cookies});
	}
	if (defined $self->{headers}->{location}) {
		push (@headers, -location => $self->{headers}->{location});
	}

	print $self->{cgi}->header(@headers);
}

1;
