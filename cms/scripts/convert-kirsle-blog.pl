#!/usr/bin/perl -w

# Generate a new salt and hash a given password with it.

scalar(@ARGV) >= 1 or die "Usage: $0 <path to old cms home dir>\n"
	. "Example: $0 \$HOME/kbackupd/home/kirsle/cms-pvt/home/kirsle\n"
	. "Converts blog data from old Siikir CMS.\n";

my $oldbase = shift(@ARGV);
my @parts   = split(/\//, $oldbase);
my $username = pop(@parts);

print "Resolved username: $username\n";

use lib "../src";
use Siikir;
use URI::Escape;

my $cms = Siikir->new (
	debug => $ENV{X_SIIKIR_DEBUG} || 0,
	root  => "..",
);
$cms->loadPlugin("User");
$cms->loadPlugin("Blog");
$cms->loadPlugin("Comment");

# Get the UID.
my $uid = $cms->User->getIdByName($username);
print "New Siikir UserID: $uid\n";

# Get all the posts.
print "Reading old blog posts...\n";
opendir (DIR, "$oldbase/blog/entries") or die "Can't readdir $oldbase/blog/entries: $!";
foreach my $file (sort { $a cmp $b } (grep(/\.txt$/i, readdir(DIR)))) {
	my $id = $file;
	$id =~ s/\.txt$//i;
	print ":: Read ID: $id\n";

	my %post = ();
	open (READ, "$oldbase/blog/entries/$file");
	my @data = <READ>;
	close (READ);
	chomp @data;

	my $inhead = 1;
	my @body = ();
	foreach my $line (@data) {
		$line = Siikir::Util::trim($line);
		$line =~ s/[\x0D\x0A]+//g;
		if (length $line == 0 && $inhead) {
			# End of headers.
			$inhead = 0;
			next;
		}
		if ($inhead) {
			# Headers.
			my ($key,$value) = split(/:\s+/, $line, 2);
			$post{ lc($key) } = $value;
		}
		else {
			push (@body, $line);
		}
	}

	$post{body} = join("\n", @body);

	my @categories = split(/\,/, $post{categories});
	foreach my $cat (@categories) {
		$cat = Siikir::Util::trim($cat);
	}

	print "\tConverting post: $post{subject}\n";

	my ($new_id,$fid) = $cms->Blog->postEntry ($uid,
		id        => $id,
		time      => $post{time},
		author    => $uid,
		subject   => $post{subject},
		avatar    => $post{avatar},
		categories => [ @categories ],
		privacy    => $post{privacy},
		emoticons  => $post{emoticons},
		comments   => $post{replies},
		body       => $post{body},
		ip         => $post{ip},
	);

	if (!defined $new_id) {
		die "Conversion failed: $@";
	}

	print "\tNew post ID: $new_id ($fid)\n";
}
closedir (DIR);

# Get all the comments.
print "Reading old blog comments...\n";
opendir (DIR, "$oldbase/comments") or die "Can't readdir $oldbase/comments: $!";
foreach my $file (sort { $a cmp $b } (grep(/\.txt$/i, readdir(DIR)))) {
	print ":: Read comment thread: $file\n";

	my @comments = ();
	open (READ, "$oldbase/comments/$file");
	my @data = <READ>;
	close (READ);
	chomp @data;

	# Parse the comments.
	foreach my $line (@data) {
		chomp $line;
		$line = Siikir::Util::trim($line);
		next if length $line == 0;

		my @pairs = split(/\&/, $line);
		my $hash  = {};
		foreach my $pair (@pairs) {
			my ($what,$is) = split(/=/, $pair, 2);
			$is = uri_unescape($is);
			$hash->{$what} = $is;
		}

		push (@comments, $hash);
	}

	# What was the comment for?
	if ($file =~ /^blog\-$username\-(\d+?)\.txt$/i) {
		my $id = $1;
		print "\tBlog comments on $id\n";
		foreach my $comment (@comments) {
			# If not a guest...
			my $cid = 0;
			if ($comment->{name} =~ /^guest:/) {
				$comment->{name} =~ s/^guest://g;
			}
			else {
				$cid = $cms->User->getIdByName($comment->{name});
				$cid = 0 unless defined $cid;
			}

			print "\t\t[$comment->{name} - $cid] $comment->{body}\n";

			my $ok = $cms->Comment->addComment ($uid, "blog-$id",
				uid     => $cid,
				name    => $comment->{name} || "Anonymous",
				message => $comment->{body},
				time    => $comment->{time},
				ip      => $comment->{ip},
				noemail => 1,
			);
			if (!$ok) {
				die "Failed to add comment: $@";
			}
		}
	}
	elsif ($file eq "guestbook.txt") {
		print "\tFound guestbook\n";
		foreach my $comment (@comments) {
			# If not a guest...
			my $cid = 0;
			if ($comment->{name} =~ /^guest:/) {
				$comment->{name} =~ s/^guest://g;
			}
			else {
				$cid = $cms->User->getIdByName($comment->{name});
				$cid = 0 unless defined $cid;
			}

			$cms->Comment->addComment ($uid, "guestbook",
				uid     => $cid,
				name    => $comment->{name} || "Anonymous",
				message => $comment->{body},
				time    => $comment->{time},
				ip      => $comment->{ip},
				noemail => 1,
			);
		}
	}
}
closedir (DIR);
