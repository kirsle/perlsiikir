package Siikir::Util 2012.0112;

use 5.14.0;
use strict;
use warnings;
use Carp;
use Time::Format qw(time_format);
use utf8;
use Encode;
use Net::DNS;

=head1 NAME

Siikir::Util - Utility methods.

=head1 METHODS

=head2 string randomHash (int length = 16)

Generate a random hash of characters with the specified length.

=cut

sub randomHash {
	my $length = shift || 16;

	my @chars = qw(
		A B C D E F G H I J K L M N O P Q R S T U V W X Y Z
		a b c d e f g h i j k l m n o p q r s t u v w x y z
		0 1 2 3 4 5 6 7 8 9
	);

	my $hash = '';
	while (length $hash < $length) {
		$hash .= $chars [ int(rand(scalar(@chars))) ];
	}

	return $hash;
}

=head2 string stripPaths (string)

Format a string to make it safe for the filesystem.

This also untaints the string.

Allowed symbols:

  A-Z a-z 0-9 . - _ {space}

=cut

sub stripPaths {
	my $string = shift;
	return undef unless defined $string;

	# First remove the characters except the safe ones.
	$string =~ s/[^A-Za-z0-9\.\-\_ ]+//g;

	# Now untaint the string.
	if ($string =~ /^([A-Za-z0-9\.\-\_ ]+)$/) {
		return $1;
	}
	else {
		return "";
	}
}

=head2 string stripSimple (string)

Removes most characters from a string. Allowed symbols:

  A-Z a-z 0-9 . - _ {space}

This also untaints the string.

=cut

sub stripSimple {
	my $string = shift;
	return undef unless defined $string;

	# Remove unsafe characters.
	$string =~ s/[^A-Za-z0-9\.\-\_ ]+//g;

	# Untaint it.
	if ($string =~ /^([A-Za-z0-9\.\-\_ ]+)$/) {
		return $1;
	}
	else {
		return "";
	}
}

=head2 string stripHTML (string)

Strip all nasty characters. HTML entities are stripped along with anything that
has a hex value below 0x20, except for newline characters.

HTML entities are also escaped.

=cut

sub stripHTML {
	my $string = shift;
	return undef unless defined $string;
	$string =~ s/&/&amp;/g;
	$string =~ s/</&lt;/g;
	$string =~ s/>/&gt;/g;
	$string =~ s/"/&quot;/g;
	$string =~ s/'/&apos;/g;
	for (my $i = 0x00; $i < 0x20; $i++) {
		next if ($i == 0x0D || $i == 0x0A); # Save newlines.
		my $byte = chr($i);
		$string =~ s/\Q$byte\E+//g;
	}
	return $string;
}

=head2 string stripUsername (string)

Strip illegal characters and normalize a username.

This also untaints the string.

=cut

sub stripUsername {
	my $string = shift;
	return undef unless defined $string;
	$string = lc($string);

	# Remove unsafe characters first.
	$string =~ s/[^A-Za-z0-9\.\-\_]+//g;

	# Only safe ones remain?
	if ($string =~ /^([A-Za-z0-9\.\-\_]+)$/) {
		return $1;
	}
	else {
		return "";
	}
}

=head2 string stripHex (string)

Strip non-hexadecimal characters from a string.

This also untaints the string.

=cut

sub stripHex {
	my $string = shift;
	return undef unless defined $string;

	# Remove unsafe chars first.
	$string =~ s/[^A-Fa-f0-9]+//g;

	# Untaint it.
	if ($string =~ /^([A-Fa-f0-9]+)$/) {
		return $1;
	}
	else {
		return "";
	}
}

=head2 int stripID (int)

Strip non-numeric characters from a string.

This also untaints a string.

=cut

sub stripID {
	my $int = shift;
	return undef unless defined $int;

	# Remove unsafe chars first.
	$int =~ s/[^0-9]+//g;

	# Untaint it.
	if ($int =~ /^([0-9]+)$/) {
		return $1;
	}
	else {
		return "";
	}
}

=head2 string trim (string)

Remove leading and trailing spaces from the string.

=cut

sub trim {
	my $string = shift;
	$string =~ s/^[\x0A\x0D\s\t]+//g;
	$string =~ s/[\x0A\x0D\s\t]+$//g;
	return $string;
}

=head2 data clone (data)

Clone a data structure, removing it from referencing the original data. Only
works on hash and array references (and multi-level hashes and arrays).

=cut

sub clone {
	my $data = shift;

	# The new clone. Unknown data type.
	my $clone;

	# Start cloning stuff!
	if (ref($data) eq "HASH") {
		$clone = {};

		foreach my $key (keys %{$data}) {
			# Another reference?
			if (ref($data->{$key})) {
				# Clone this tree too.
				$clone->{$key} = clone($data->{$key});
			}
			else {
				# Copy the scalar across.
				$clone->{$key} = $data->{$key};
			}
		}
	}
	elsif (ref($data) eq "ARRAY") {
		$clone = [];

		foreach my $item (@{$data}) {
			# Another reference?
			if (ref($item)) {
				# Clone this too.
				push (@{$clone}, clone($item));
			}
			else {
				# Copy the scalar across.
				push (@{$clone}, $item);
			}
		}
	}
	elsif (ref($data)) {
		# Fatal (this shouldn't happen, and when it does, it's a real bug!)
		confess "Failed to clone data: not a HASH or ARRAY reference!";
	}
	else {
		# Can't clone a simple scalar.
		$clone = $data;
	}

	# Return the clone.
	return $clone;
}

=head2 data utf8_decode (data)

Recursively UTF8-decode a data structure. Any data structure.

Decoding turns on the UTF-8 flag in Perl and makes Perl treat the data as
string (so methods like C<length()> are accurate). If you want to print the
data to a text file, you need to B<encode> it into bytes.

=cut

sub utf8_decode {
	my $data = shift;
	my $encode = shift || 0;

	# If it's a data structure (hash or array), recurse over its contents.
	if (ref($data) eq "HASH") {
		foreach my $key (keys %{$data}) {
			# Another data structure?
			if (ref($data->{$key})) {
				# Recurse.
				$data->{$key} = utf8_decode($data->{$key}, $encode);
				next;
			}

			# Encode the scalar.
			$data->{$key} = utf8_decode($data->{$key}, $encode);
		}
	}
	elsif (ref($data) eq "ARRAY") {
		foreach my $key (@{$data}) {
			# Another data structure?
			if (ref($key)) {
				# Recurse.
				$key = utf8_decode($key, $encode);
				next;
			}

			# Encode the scalar.
			$key = utf8_decode($key, $encode);
		}
	}
	else {
		# This is a leaf node in our data (a scalar). Encode UTF-8!
		my $is_utf8 = utf8::is_utf8($data);

		# Are they *encoding* (turning into bytes) instead of *decoding*?
		if ($encode) {
			# Encoding (making bytestream): only decode IF it is currently UTF8.
			return $data unless $is_utf8;
			$data = Encode::encode("UTF-8", $data);
		}
		else {
			# Decoding. If it's ALREADY UTF-8, do not decode it again.
			return $data if $is_utf8;
			$data = Encode::decode("UTF-8", $data);
		}
	}

	return $data;
}

=head2 data utf8_encode (data)

Recursively UTF8 encode a data structure. B<Encoding> means turning the data
into a byte stream (so string operators like C<length()> will be inaccurate).

Encoding is necessary to transmit a Unicode string over a network.

=cut

sub utf8_encode {
	my $data = shift;
	use Data::Dumper;
	return utf8_decode($data, 1);
}

=head2 string formatDOB (year, month, day)

Format a birthdate into a standard yyyy-mm-dd string.

=cut

sub formatDOB {
	my ($year,$month,$day) = @_;
	return join("-",
		sprintf("%4d", $year),
		sprintf("%02d", $month),
		sprintf("%02d", $day),
	);
}

=head2 int getAge (string DOB)

Get the age of a user from their DOB string in yyyy-mm-dd format.

=cut

sub getAge {
	my $dob = shift;

	my ($year,$month,$day) = split(/\-/, $dob, 3);

	# First subtract the year from now.
	my $nowYear  = time_format("yyyy", time());
	my $nowMonth = time_format("mm{on}", time());
	my $nowDay   = time_format("dd", time());

	my $age = $nowYear - $year;
	return -1 if $age < 0;

	# Has their month come yet?
	if ($month > $nowMonth) {
		# Not yet.
		$age--;
	}
	elsif ($month == $nowMonth) {
		# This is their birth month. Has the day come?
		if ($day > $nowDay) {
			# No.
			$age--;
		}
	}

	return $age;
}

=head2 data getZipcode (int zipcode)

Retrieve data about a US zipcode. Returns undef if not found.

Data returns is a hash including:

  city
  state
  latitude
  longitude

=cut

sub getZipcode {
	my $zip = shift;

	# Gulp?
	require Siikir::Geo;
	if (exists $Siikir::Geo::zips->{$zip}) {
		my @data = @{$Siikir::Geo::zips->{$zip}};
		return {
			city      => $data[0],
			state     => $data[1],
			latitude  => $data[2],
			longitude => $data[3],
		};
	}

	return undef;
}

=head2 float getDistance (lat1, long1, lat2, long2)

Given two pairs of geo coordinates, return the distance between them in feet.

=cut

our $pi = atan2(1,1) * 4;
sub getDistance {
	my ($lat1, $lon1, $lat2, $lon2) = @_;

	sub acos {
		my $rad = shift;
		my $ret;
		eval {
			$ret = atan2(sqrt(1 - $rad**2), $rad);
		};
		return $ret;
	}

	sub deg2rad {
		my $deg = shift;
		return ($deg * $pi / 180);
	}

	sub rad2deg {
		my $rad = shift;
		return ($rad * 180 / $pi);
	}

	my $theta = $lon1 - $lon2;
	my $dist  = sin(deg2rad($lat1)) * sin(deg2rad($lat2)) + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * cos(deg2rad($theta));
	$dist = acos($dist);
	$dist = rad2deg($dist);
	$dist = $dist * 60 * 1.1515;
	return $dist;
}

=head2 bool isTor ()

Detect whether the end user is using the Tor network. This relies on the
environment variables C<REMOTE_ADDR>, C<SERVER_ADDR>, and C<SERVER_PORT>.

=cut

sub isTor {
	my $hostname = join(".",
		reverseIP($ENV{REMOTE_ADDR}),
		$ENV{SERVER_PORT},
		reverseIP($ENV{SERVER_ADDR}),
		"ip-port.exitlist.torproject.org",
	);

	my $res = Net::DNS::Resolver->new;
	my $q   = $res->search($hostname);
	if ($q) {
		foreach my $rr ($q->answer) {
			next unless $rr->type eq 'A';
			if ($rr->address eq '127.0.0.2') {
				return 1;
			}
		}
	}

	return undef;
}

=head2 string reverseIP (string IP)

Reverse the octets in an IP address.

=cut

sub reverseIP {
	my $ip = shift;
	my @octets = split(/\./, $ip);
	return join(".", reverse(@octets));
}

=head2 data paramFields (aref fields, data param[, hash options])

A utility function to help with profile page submissions or plugin config
submissions. Pass C<fields> which is a data structure like "fields" in
Profile plugin, and C<param> is the HTTP params from C<$vars-E<gt>{param}>.

Returns a hash reference with the following data:

  warnings => [ warnings encountered ],
  errors   => [ errors encountered ],
  fields   => { normalized field/value pairs },

Optional fields to pass are:

  bool allowhtml => Do not filter HTML

=cut

sub paramFields {
	my ($schema,$param,%opts) = @_;

	# Construct run-time data.
	my $warnings = [];
	my $errors   = [];
	my $fields   = {};

	# Loop over the schema and cherry-pick values from the params.
	foreach my $category (@{$schema}) {

		# Loop over the fields in this category.
		foreach my $field (@{$category->{fields}}) {
			next unless exists $field->{name};
			next unless exists $field->{type};

			# The height type field has two params.
			if ($field->{type} eq "height") {
				foreach my $tag (qw(feet inches)) {
					my $name  = join("-", $field->{name}, $tag);

					my $value = $param->{$name};
					if (length $value && $value =~ /^[0-9]+$/) {
						$fields->{$name} = $value;
					}
					elsif (length $value == 0) {
						$fields->{$name} = "";
					}
					elsif (length $value) {
						push (@{$errors}, "Given height (in $tag) is not a valid number!");
					}
				}

				next;
			}

			# Get the value from param.
			my $name  = $field->{name};
			my $value = $param->{$name} || '';

			# Verify it based on type.
			my $type = $field->{type};
			if ($type eq "text" || $type eq "essay" || $type eq "timezone") {
				# Text field. Simple.
				$fields->{$name} = $opts{allowhtml} ? $value : stripHTML($value);
			}
			elsif ($type eq "number") {
				# A number field.
				if (length $value && $value !~ /^[0-9]+?$/) {
					push (@{$errors}, "The field $field->{label} requires a numeric value!");
					next;
				}

				# Does it have a size range?
				if ($field->{minlength} && length($value) < $field->{minlength}) {
					push (@{$errors}, "The $field->{label} must be at least $field->{minlength} digits long.");
					next;
				}
				if ($field->{maxlength} && length($value) > $field->{maxlength}) {
					push (@{$errors}, "The $field->{label} must be no more than $field->{maxlength} digits long.");
					next;
				}

				# All good by now!
				$fields->{$name} = $value;
			}
			elsif ($type eq "number-range") {
				# Select box with number range. Simple.
				if (length $value && $value !~ /^\d+$/) {
					push (@{$errors}, "Number-range field $field->{label} requires a numeric value!");
					next;
				}

				if (length $value && $value < $field->{low}) {
					push (@{$errors}, "The $field->{label} must be at least $field->{low}.");
					next;
				}
				if (length $value && $value > $field->{high}) {
					push (@{$errors}, "The $field->{label} must be no higher than $field->{high}.");
					next;
				}

				# All good!
				$fields->{$name} = $value;
			}
			elsif ($type eq "select" || $type eq "radio") {
				# Selectable field. Simple.
				$fields->{$name} = $opts{allowhtml} ? $value : stripHTML($value);
			}
			elsif ($type eq "checkgroup") {
				# A checkgroup will have many values.
				$fields->{$name} = ref($value) eq "ARRAY" ? join(", ", @{$value}) : $value;
				$fields->{$name} = $opts{allowhtml} ? $value : stripHTML($fields->{$name});
			}
			else {
				die "Unknown field type '$type'!";
			}
		}
	}

	# Return the data.
	return {
		errors   => $errors,
		warnings => $warnings,
		fields   => $fields,
	};
}

1;
