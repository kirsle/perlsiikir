package Siikir::Plugin::Comment 2012.0609;

use 5.14.0;
use strict;
use warnings;
use Siikir::Util;
use URI::Escape;

use base "Siikir::Plugin";

=head1 NAME

Siikir::Plugin::Comment - Generic page comment support.

=cut

sub init {
	my $self = shift;

	$self->debug("Comment plugin loaded!");
	$self->requires(qw(User Facebook Messaging JsonDB));

	# Options.
	$self->options(
		# Send notification messages how?
		notify => "email", # or "messaging"
		sender => 1,       # sender
	);

	# Interface.
	$self->interface([
		{
			category => "Comment Settings",
			fields   => [
				{ section => "Behavior" },
				{
					name    => "notify",
					label   => "Notification Method",
					text    => "Specify how comment notifications are to be delivered to the owners.",
					type    => "radio",
					options => [
						"email" => "Send an e-mail directly (if the owner has a valid e-mail address)",
						"messaging" => "Use the Messaging plugin (sends them a message on the site, which may also trigger an e-mail)",
						""          => "Do not send notifications about comments.",
					],
				},
				{
					name    => "sender",
					label   => "User ID of Sender",
					text    => "The user ID number of the user that sends in-site messages (if the Notification Method is 'messaging'). Default is 1 for the admin.",
					type    => "number",
				},
			],
		},
	]);
}

=head1 METHODS

=head2 bool addComment (string owner, string thread, hash options)

Publish a comment on a C<thread> that is owned by C<owner>. Options include:

  int uid:        ID of the user posting the comment (0 for guest comments)
  string name:    The name of the commenter (if a guest)
  string image:   URL to their facebook image (if available)
  string message: The message to post.
  string subject: Subject for the notification e-mail.
  string url:     URL where the comment can be seen.
  int time:       Epoch time of the comment.
  string ip:      IP address of the commenter.
  bool noemail:   If true, no notification e-mail is sent.

=cut

sub addComment {
	my ($self,$owner,$thread,%opts) = @_;
	$owner  = Siikir::Util::stripID($owner);
	$thread = Siikir::Util::stripSimple($thread);
	my $uid = Siikir::Util::stripID($opts{uid});

	# Owner must exist.
	if (!$self->Master->User->userExists(id => $owner)) {
		$@ = "Comment owner ID $owner not found.";
		return undef;
	}

	# Get the comments for this thread.
	my $comments = $self->getComments($owner, $thread);

	# Make up a unique ID for the comment.
	my $id = Siikir::Util::randomHash();
	while (exists $comments->{$id}) {
		$id = Siikir::Util::randomHash();
	}

	# Add the comment.
	$comments->{$id} = {
		uid     => $uid,
		name    => $opts{name} || "Anonymous",
		image   => $opts{image} || "",
		message => $opts{message},
		time    => $opts{time} || time(),
		ip      => $opts{ip} || $ENV{REMOTE_ADDR},
	};

	# Save them.
	$self->Master->JsonDB->writeDocument("comments/$owner/$thread", $comments);

	# Get info about the commenter.
	my $name = $opts{name} || "Anonymous";
	if ($self->Master->User->userExists(id => $uid)) {
		my $profile = $self->Master->Profile->getProfile($uid);
		$name = $profile->{displayname};
	}

	# Send the e-mail.
	unless ($opts{noemail}) {
		# How are we notifying them?
		if ($self->{notify} eq "messaging") {
			# Send an in-site message.
			$self->Master->Messaging->sendMessage (
				to      => $owner,
				from    => $self->{sender} || $owner,
				subject => "New Photo Comment!",
				message => "<strong>$name</strong> has left a comment on one of your photos.\n\n"
					. "To view the comment, please go to: <a href=\"$opts{url}\">$opts{url}</a>.\n\n"
					. "<hr>\n"
					. "This message was automatically generated. Do not reply to it.",
				html    => 1,
			);
		}
		elsif ($self->{notify} eq "email") {
			$self->Master->Messaging->email (
				to      => $owner,
				class   => "comment",
				subject => "New Comment: $opts{subject}",
				message => "$name has left a comment on: $opts{subject}\n\n"
					. "$opts{message}\n\n"
					. "To view this comment, please go to $opts{url}\n\n"
					. "================\n"
					. "This e-mail was automatically generated. Do not reply to it.",
			);
		}
	}

	# Notify any subscribers.
	my $db;
	if ($self->Master->JsonDB->documentExists("subscribers/comments/$owner/$thread")) {
		$db = $self->Master->JsonDB->getDocument("subscribers/comments/$owner/$thread");
		foreach my $subscriber (keys %{$db}) {
			my $email = $subscriber;
			if ($subscriber =~ /^\d+$/ && $self->Master->User->userExists(id => $subscriber)) {
				my $profile = $self->Master->Profile->getProfile($subscriber);
				$email = $profile->{email};
			}

			# Send mail.
			my $unsub = "http://$ENV{SERVER_NAME}/comment?do=unsubscribe&u="
				. uri_escape($owner) . "&thread=" . uri_escape($thread)
				. "&who=" . uri_escape($subscriber);
			$self->Master->Messaging->email (
				email   => $email,
				class   => "subscribe",
				subject => "New Comment: $opts{subject}",
				message => qq{Hello,

You are currently subscribed to the comment thread '$thread', and somebody has
just added a new comment!

$name has left a comment on: $opts{subject}

$opts{message}

To view this comment, please go to $opts{url}

================

This e-mail was automatically generated. Do not reply to it.

If you wish to unsubscribe from this comment thread, please visit the following
URL: $unsub},
			);
		}
	}

	return 1;
}

=head2 href getComments (string owner, string thread)

Get the comments for the thread.

=cut

sub getComments {
	my ($self,$owner,$thread) = @_;
	$owner  = Siikir::Util::stripUsername($owner);
	$thread = Siikir::Util::stripSimple($thread);

	# Owner must exist.
	if (!$self->Master->User->userExists(id => $owner)) {
		$@ = "Comment owner ID $owner not found.";
		return undef;
	}

	# Get the DB.
	if (!$self->Master->JsonDB->documentExists("comments/$owner/$thread")) {
		return {};
	}

	return $self->Master->JsonDB->getDocument("comments/$owner/$thread");
}

=head2 bool deleteComment (string owner, string thread, string commentid)

Delete a comment.

=cut

sub deleteComment {
	my ($self,$owner,$thread,$comment) = @_;
	$owner  = Siikir::Util::stripUsername($owner);
	$thread = Siikir::Util::stripSimple($thread);

	# Owner must exist.
	if (!$self->Master->User->userExists(id => $owner)) {
		$@ = "Comment owner ID $owner not found.";
		return undef;
	}

	# Get the comments for this thread.
	my $comments = $self->getComments($owner, $thread);

	# Delete the comment.
	delete $comments->{$comment};
	$self->Master->JsonDB->writeDocument("comments/$owner/$thread", $comments);

	return 1;
}

=head2 bool addSubscriber (string owner, string thread, string subscriber)

Add a subscriber to the comment thread. If C<subscriber> is a number, it will
be treated as a Siikir User ID. Otherwise, C<subscriber> should be a valid
e-mail address.

The subscriber will be sent a confirmation e-mail.

=cut

sub addSubscriber {
	my ($self,$owner,$thread,$subscriber) = @_;
	$owner  = Siikir::Util::stripUsername($owner);
	$thread = Siikir::Util::stripSimple($thread);

	# Owner must exist.
	if (!$self->Master->User->userExists(id => $owner)) {
		$@ = "Comment owner ID $owner not found.";
		return undef;
	}

	# Is the subscriber a user ID?
	my $email;
	if ($subscriber =~ /^\d+$/) {
		if ($self->Master->User->userExists(id => $subscriber)) {
			# Get their e-mail.
			my $profile = $self->Master->Profile->getProfile($subscriber);
			if ($profile->{email}) {
				$email = $profile->{email};
			}
		}
		else {
			$@ = "Subscriber user ID $subscriber not found.";
			return undef;
		}
	}
	else {
		$email = $subscriber;
	}

	# Validate the e-mail.
	if ($email !~ /^.+\@.+\..+$/) {
		$@ = "Invalid e-mail address. Can't subscribe.";
		return undef;
	}

	# Add them as a subscriber.
	my $db;
	if ($self->Master->JsonDB->documentExists("subscribers/comments/$owner/$thread")) {
		$db = $self->Master->JsonDB->getDocument("subscribers/comments/$owner/$thread");
	}

	$db->{$subscriber} = time();
	$self->Master->JsonDB->writeDocument("subscribers/comments/$owner/$thread", $db);

	# URI encode params.
	my $url = "http://$ENV{SERVER_NAME}/comment?do=unsubscribe";
	my %u = (
		thread => $url . "&u=" . uri_escape($owner) . "&thread=" . uri_escape($thread)
			. "&who=" . uri_escape($subscriber),
		global => "http://$ENV{SERVER_NAME}/comment/privacy",
	);

	# Send notification e-mail.
	$self->Master->Messaging->email (
		email => $email,
		class => 'subscribe',
		subject => "Subscribed to a new comment thread",
		message => qq{Hello,

This e-mail is to confirm that you have been subscribed to a comment thread on
$ENV{SERVER_NAME}. The comment thread you've been subscribed to is called
"$thread".

When people add comments to this thread in the future, you will receive e-mail
notifications automatically. If you ever wish to unsubscribe from this comment
thread, please visit the link below:

Thread Unsubscribe:
$u{thread}

If you wish to unsubscribe from all comment threads on $ENV{SERVER_NAME}, then
visit the link below:

Unsubscribe from All Threads:
$u{global}

---------------------------------------------------------------------

Do not respond to this e-mail. It was automatically generated.},
	);

	return 1;
}

=head2 bool removeSubscriber (string owner, string thread, string subscriber)

Remove a subscriber from a thread. If the C<owner> is undefined, they will be
removed from all threads by all owners.

The subscriber will be sent a confirmation email.

=cut

sub removeSubscriber {
	my ($self,$owner,$thread,$subscriber) = @_;
	$owner  = Siikir::Util::stripUsername($owner);
	$thread = Siikir::Util::stripSimple($thread);

	# Owner must exist.
	if (defined $owner && !$self->Master->User->userExists(id => $owner)) {
		$@ = "Comment owner ID $owner not found.";
		return undef;
	}

	# Is the subscriber a user ID?
	my $email;
	if ($subscriber =~ /^\d+$/) {
		if ($self->Master->User->userExists(id => $subscriber)) {
			# Get their e-mail.
			my $profile = $self->Master->Profile->getProfile($subscriber);
			if ($profile->{email}) {
				$email = $profile->{email};
			}
		}
		else {
			$@ = "Subscriber user ID $subscriber not found.";
			return undef;
		}
	}
	else {
		$email = $subscriber;
	}

	# Which threads to unsubscribe from?
	my @threads;
	if (defined $owner) {
		push (@threads, "$owner/$thread");
	}
	else {
		# All threads.
		if (-d "$self->{root}/db/subscribers/comments") {
			opendir (my $dh, "$self->{root}/db/subscribers/comments");
			foreach my $uid (sort(grep(/^\d+$/, readdir($dh)))) {
				opendir (my $th, "$self->{root}/db/subscribers/comments/$uid");
				foreach my $file (sort(grep(/\.json$/i, readdir($th)))) {
					$file =~ s/\.json$//;
					push (@threads, "$uid/$file");
				}
				closedir($th);
			}
			closedir($dh);
		}
	}

	# Remove them as a subscriber.
	foreach my $thr (@threads) {
		# Untaint.
		($thr) = ($thr =~ /^(.+?)$/);
		my $db;
		if ($self->Master->JsonDB->documentExists("subscribers/comments/$thr")) {
			$db = $self->Master->JsonDB->getDocument("subscribers/comments/$thr");
		}

		if (exists $db->{$subscriber}) {
			delete $db->{$subscriber};
			$self->Master->JsonDB->writeDocument("subscribers/comments/$thr", $db);
		}
	}

	return 1;
}

1;
