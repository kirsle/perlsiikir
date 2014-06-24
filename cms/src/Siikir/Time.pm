package Siikir::Time 1.20110521;

use 5.14.0;
use strict;
use warnings;
use Time::Format qw(time_format);
use Time::Local;
use Digest::MD5 qw(md5_hex);
use Digest::SHA1 qw(sha1_hex);

our $VERSION = '0.01';

=head1 NAME

Siikir::Time - Utility functions to help with time zone stuff.

=head1 DESCRIPTION

This module is used only for its methods; it is not an object-oriented module.

  my $stamp = Siikir::Time::getTimestamp('yyyy-mm-dd', time());

=head1 TIME METHODS

=head2 structure getTimezones ([bool asArray])

Retrieve the list of supported time zones. By default it will return a hash,
where the keys are the time zone labels and the values as the offsets in
seconds. When C<asArray> is true, it returns an ordered hash reference (or, a
paired array reference) in which the keys are sorted by their time offset, from
least to greatest.

  Array format:
  [
    "(GMT -11:00) Midway Island, Samoa" => -11 * 3600,
    "(GMT -10:00) Hawaii"               => -10 * 3600,
    "(GMT -9:00) Alaska"                => -9  * 3600,
    ...
  ];

=cut

sub getTimezones {
	my ($asArray) = @_;

	# Time zone structure.
	my $zones = [
		"(GMT -11:00) Midway Island, Samoa"                    => (-11 * 3600),
		"(GMT -10:00) Hawaii"                                  => (-10 * 3600),
		"(GMT -9:00) Alaska"                                   => (-9 * 3600),
		"(GMT -8:00) Pacific Time (US &amp; Canada)"           => (-8 * 3600),
		"(GMT -7:00) Mountain Time (US &amp; Canada)"          => (-7 * 3600),
		"(GMT -6:00) Central Time (US &amp; Canada)"           => (-6 * 3600),
		"(GMT -5:00) Eastern Time (US &amp; Canada)"           => (-5 * 3600),
		"(GMT -4:30) Caracas"                                  => (-5 * 3600 - 1800),
		"(GMT -4:00) Atlantic Time (Canada), La Paz, Santiago" => (-4 * 3600),
		"(GMT -3:30) Newfoundland"                             => (-4 * 3600 - 1800),
		"(GMT -3:00) Brazil, Buenos Aires, Georgetown"         => (-3 * 3600),
		"(GMT -2:00) Mid-Atlantic"                             => (-2 * 3600),
		"(GMT -1:00 hour) Azores, Cape Verde Islands"          => (-1 * 3600),
		"(GMT) Western Europe Time, London, Lisbon, Casablanca" => 0,
		"(GMT +1:00 hour) Brussels, Copenhagen, Madrid, Paris" => (1 * 3600),
		"(GMT +2:00) Kaliningrad, South Africa"                => (2 * 3600),
		"(GMT +3:00) Baghdad, Riyadh, Moscow, St. Petersburg"  => (3 * 3600),
		"(GMT +3:30) Tehran"                                   => (3 * 3600 + 1800),
		"(GMT +4:00) Abu Dhabi, Muscat, Baku, Tbilisi"         => (4 * 3600),
		"(GMT +4:30) Kabul"                                    => (4 * 3600 + 1800),
		"(GMT +5:00) Ekaterinburg, Islamabad, Karachi, Tashkent" => (5 * 3600),
		"(GMT +5:30) Mumbai, Kolkata, Chennai, New Delhi"      => (5 * 3600 + 1800),
		"(GMT +5:45) Kathmandu"                                => (5 * 3600 + 2700),
		"(GMT +6:00) Almaty, Dhaka, Colombo"                   => (6 * 3600),
		"(GMT +6:30) Yangon, Cocos Islands"                    => (6 * 3600 + 1800),
		"(GMT +7:00) Bangkok, Hanoi, Jakarta"                  => (7 * 3600),
		"(GMT +8:00) Beijing, Perth, Singapore, Hong Kong"     => (8 * 3600),
		"(GMT +9:00) Tokyo, Seoul, Osaka, Sapporo, Yakutsk"    => (9 * 3600),
		"(GMT +9:30) Adelaide, Darwin"                         => (9 * 3600 + 1800),
		"(GMT +10:00) Eastern Australia, Guam, Vladivostok"    => (10 * 3600),
		"(GMT +11:00) Megadan, Solomon Islands, New Caledonia" => (11 * 3600),
		"(GMT +12:00) Auckland, Wellington, Fiji, Kamhatka"    => (12 * 3600),
	];

	if (defined $asArray && $asArray) {
		return $zones;
	}
	else {
		my $hash = {};
		for (my $i = 0; $i < scalar @{$zones}; $i += 2) {
			$hash->{ $zones->[$i] } = $zones->[$i + 1];
		}
		return $hash;
	}
}

=head2 string getTimestamp (string format[, int epoch])

Get a pretty-formatted time stamp. C<format> is the format that you want the
time to be returned in, in a format that C<Time::Format> understands. C<epoch>
is the Unix time stamp that you want to be formatted, or else the current
C<time()>.

The time stamp returned from this function directly will be relative to the
local time of the web server. To get an offset time for a specific time zone,
use the C<getLocalTimestamp()> function instead.

The fields recognized for C<format> are as follows:

  yyyy       4-digit year
  yy         2-digit year

  m          1- or 2-digit month, 1-12
  mm         2-digit month, 01-12
  ?m         month with leading space if < 10

  Month      full month name, mixed-case
  MONTH      full month name, uppercase
  month      full month name, lowercase
  Mon        3-letter month abbreviation, mixed-case
  MON  mon   ditto, uppercase and lowercase versions

  d          day number, 1-31
  dd         day number, 01-31
  ?d         day with leading space if < 10
  th         day suffix (st, nd, rd, or th)
  TH         uppercase suffix

  Weekday    weekday name, mixed-case
  WEEKDAY    weekday name, uppercase
  weekday    weekday name, lowercase
  Day        3-letter weekday name, mixed-case
  DAY  day   ditto, uppercase and lowercase versions

  h          hour, 0-23
  hh         hour, 00-23
  ?h         hour, 0-23 with leading space if < 10

  H          hour, 1-12
  HH         hour, 01-12
  ?H         hour, 1-12 with leading space if < 10

  m          minute, 0-59
  mm         minute, 00-59
  ?m         minute, 0-59 with leading space if < 10

  s          second, 0-59
  ss         second, 00-59
  ?s         second, 0-59 with leading space if < 10
  mmm        millisecond, 000-999
  uuuuuu     microsecond, 000000-999999

  am   a.m.  The string "am" or "pm" (second form with periods)
  pm   p.m.  same as "am" or "a.m."
  AM   A.M.  same as "am" or "a.m." but uppercase
  PM   P.M.  same as "AM" or "A.M."

  tz         time zone abbreviation

=cut

sub getTimestamp {
	my ($format,$epoch) = @_;

	# If no epoch time was given, use the current time.
	if (!defined $epoch || (defined $epoch && $epoch =~ /[^0-9]/)) {
		$epoch = time();
	}

	# Format the time.
	return Time::Format::time_format ($format,$epoch);
}

=head2 string getLocalTimestamp (string format[, int epoch[, int offset]])

This is like C<getTimestamp()>, except it will offset the time returned to match
the local time of a specific time zone.

=cut

sub getLocalTimestamp {
	my ($format,$epoch,$tz) = @_;

	# If no epoch time, use the current time.
	if (!defined $epoch || (defined $epoch && $epoch =~ /[^0-9]/)) {
		$epoch = time();
	}

	# Get the current GMT time based on the server's localtime.
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime ($epoch);

	# Get the adjust epoch time back from this.
	my $gm = Time::Local::timelocal ($sec,$min,$hour,$mday,$mon,$year);
	$gm = $epoch unless defined $tz;

	# Offset the epoch time.
	if (defined $tz && $tz != 0) {
		# Need to apply daylight saving time?
		if (Siikir::Time::isDST()) {
			$tz += 3600;
		}
		$gm += $tz;
	}

	# Format the time.
	return Siikir::Time::getTimestamp ($format,$gm);
}

=head2 bool isDST ()

Returns 1 if daylight saving time is currently being observed. Undef
otherwise.

=cut

sub isDST {
	my ($isdst) = (localtime(time()))[8];
	return $isdst ? 1 : undef;
}

1;
