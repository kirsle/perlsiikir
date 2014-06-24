package Siikir::API 2011.0624;

use 5.14.0;
use strict;
use warnings;
use JSON;

# JSON flags
my $flags = {
	utf8   => 1,
	pretty => 1,
};

=head1 NAME

Siikir::API - API utility methods.

=head1 METHODS

=head2 string toJSON (data)

Convert C<data> to a JSON data structure.

=cut

sub toJSON {
	my $data = shift;
	return to_json ($data, $flags);
}

=head2 data fromJSON (string)

Convert C<string> from JSON to a Perl data structure.

=cut

sub fromJSON {
	my $json = shift;
	return from_json ($json, $flags);
}

1;
