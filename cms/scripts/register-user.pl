#!/usr/bin/perl -w

# Register a new user
use lib "../src";
use strict;
use Siikir;

my $cms = Siikir->new(
	debug => $ENV{X_SIIKIR_DEBUG} || 0,
	root  => "..",
);
$cms->loadPlugin("JsonDB");
$cms->loadPlugin("User");
$cms->loadPlugin("Profile");

print "Register a New User\n\n";

my $uid = prompt("Enter a user ID or blank for auto", "", sub {
	my $ans = shift;
	if ($ans !~ /^\d+$/) {
		return "User IDs must be numeric!";
	}
	elsif ($ans == 0) {
		return "User ID 0 is reserved for the guest user!";
	}
	elsif ($cms->User->userExists(id => $ans)) {
		return "That user ID is already taken!";
	}
	return undef;
});

my $username = prompt("Enter a log-in username", undef, sub {
	my $ans = shift;
	if (!$cms->User->validUsername($ans)) {
		return "That username isn't valid: $@";
	}
	if ($cms->User->userExists(name => $ans)) {
		return "That user name is already taken!";
	}
	return undef;
});

my $admin = prompt("Is this an admin user? Type 'yes' if so, or enter if not", "", sub {
	my $ans = shift;
	if ($ans ne "yes") {
		return "Only type 'yes' if this is an admin; enter nothing if not.";
	}
});

my $password = prompt("Enter a password");
my $dob = prompt("Enter a birthdate in yyyy-mm-dd format", undef, sub {
	my $ans = shift;
	if ($ans !~ /^\d{4}\-\d{2}\-\d{2}$/) {
		return "Birthdate must be in yyyy-mm-dd format!";
	}
	elsif (Siikir::Util::getAge($ans) < 18) {
		return "Users must be at least 18 years old!";
	}
	return undef;
});

my $nick = prompt("Enter their name or nickname (optional)", "");
my $email = prompt("Enter their e-mail address (optional)", "");
my $sex   = prompt("Enter their gender <male|female> (optional)", "", sub {
	my $ans = shift;
	if ($ans ne "male" && $ans ne "female") {
		return "Answer must be 'male' or 'female', or empty for not specified.";
	}
	return undef;
});
my $zip = prompt("Enter their US zip code (optional)", "");

# Try to create the user.
my @user = (
	username => $username,
	password => $password,
	dob      => $dob,
);
if (length $uid) {
	push (@user, id => $uid);
}
if ($admin eq "yes") {
	print "User will be created with admin privileges.\n";
	push (@user, level => "admin");
}
$uid = $cms->User->addUser(@user);
if (!defined $uid) {
	die "Failed to register this user: $@";
}

print "\n\nUser ID $uid has been created.\n";

# Initialize their profile.
$cms->Profile->setFields($uid, {
	nickname  => $nick,
	first_name => $nick,
	email      => $email,
	gender     => $sex,
	timezone   => 0,
	zipcode    => $zip,
});
print "Created their initial profile.\n\n"
	. "Username '$username' successfully created.\n";

sub prompt {
	my ($question, $default, $handler) = @_;

	while (1) {
		print "$question> ";
		chomp(my $answer = <STDIN>);
		if (defined $default) {
			return $default unless length $answer;
		}
		elsif (!defined $default && length $answer == 0) {
			print "This question requires an answer.\n\n";
			next;
		}
		if ($handler) {
			my $res = $handler->($answer);
			if ($res) {
				print "$res\n\n";
				next;
			}
		}
		return $answer;
	}
}
