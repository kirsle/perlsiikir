#!/usr/bin/perl -w

# Generate a new salt and hash a given password with it.

scalar(@ARGV) >= 2 or die "Usage: $0 <user id> <plain text password> [salt]\n"
	. "Generates a new salt and hashes the password with it.\n";

my $uid  = shift(@ARGV);
my $pass = shift(@ARGV);
my $salt;
if (@ARGV) {
	$salt = shift(@ARGV);
}

use lib "../src";
use Siikir;

my $cms = Siikir->new(
	debug => $ENV{X_SIIKIR_DEBUG} || 0,
	root  => "..",
);
$cms->loadPlugin("User");

$salt  ||= $cms->User->generateSalt();
my $hash = $cms->User->salt($uid, $pass, $salt);

print "User ID: $uid\n"
	. "Passwd:  $pass\n"
	. "Salt:    $salt\n"
	. "Hash:    $hash\n";

