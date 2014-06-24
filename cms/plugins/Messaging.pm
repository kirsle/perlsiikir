package Siikir::Plugin::Messaging 2012.0609;

use 5.14.0;
use strict;
use warnings;
use Image::Magick;
use LWP::Simple;
use Digest::MD5 qw(md5_hex);
use File::Copy;

use base "Siikir::Plugin";

=head1 NAME

Siikir::Plugin::Messaging - Let users send each other messages. Also handle SMTP
dispatching.

=cut

sub init {
	my $self = shift;

	$self->debug("Messaging plugin loaded!");

	# Options.
	$self->options(
		# Mail server options.
		method   => "smtp", # or sendmail
		server   => "localhost",
		port     => 25,
		sender   => "Siikir <auto\@siikir.com>",
		command  => "/usr/sbin/sendmail -t",
	);

	# Interface.
	$self->interface([
		{
			category => "Messaging Settings",
			fields   => [
				{ section => "Mail Settings" },
				{
					name    => "method",
					label   => "Mail Method",
					text    => "Which system should be used for sending e-mail?",
					type    => "radio",
					options => [
						"smtp"     => "SMTP Server (default)",
						"sendmail" => "Unix sendmail",
					],
				},
				{
					name    => "sender",
					label   => "Sender",
					text    => "The name and e-mail of the sender, in the format: Some Name &lt;some\@name.com&gt;",
					type    => "text",
				},
				{ section => "SMTP Settings" },
				{
					name    => "server",
					label   => "Mail Server",
					type    => "text",
				},
				{
					name    => "port",
					label   => "SMTP Server Port",
					type    => "number",
				},
				{ section => "Unix Sendmail Settings" },
				{
					name    => "command",
					label   => "Sendmail binary and params (usually /usr/sbin/sendmail -t)",
					type    => "text",
				},
			],
		}
	]);
}

=head1 METHODS

=head2 bool email (hash options)

Send an e-mail to a user of the site. Options include:

  int    to:      The user ID of the recipient
  string email:  Email address to send to (optional)
  string class:  The "class" of mail (e.g. the part of the site it came from). NOT USED YET
  string subject
  string message
  string replyto: Optional, set a Reply-To header.

The preferred way is to give a user ID; if that ID has an e-mail address
on file, the mail will be sent to that address. If you want to send to
a specific address, however, provide C<email>.

Returns undef and sets C<$@> on error (most likely: the user doesn't have
an e-mail address on file. This is only useful i.e. for a password recovery
system.

=cut

sub email {
	my ($self,%opts) = @_;

	# Collect opts.
	my $email = $opts{email}     || undef;
	my $class = $opts{class}     || "general";
	my $subject = $opts{subject} || "[no subject]";
	my $message = $opts{message} || undef;
	my $replyto = $opts{replyto} || undef;

	# Fix quotes for the e-mail.
	$subject =~ s/\&quot;/"/g;
	$subject =~ s/\&apos;/'/g;
	$message =~ s/\&quot;/"/g;
	$message =~ s/\&apos;/'/g;

	# Given a user ID?
	if ($opts{to}) {
		my $id = $opts{to};
		$id =~ s/[^\d]+//g;
		if (!$self->Master->User->userExists(id => $id)) {
			$@ = "User ID $id not found!";
			return undef;
		}

		# Get their profile e-mail.
		my $profile = $self->Master->Profile->getProfile($id);
		if (!exists $profile->{email} || $profile->{email} !~ /^.+\@.+\..+$/) {
			$@ = "There is no valid e-mail address on file for this user.";
			return undef;
		}

		$email = $profile->{email};
	}

	# Validation.
	if (!defined $email) {
		$@ = "No e-mail address provided to send mail to.";
		return undef;
	}
	elsif (!defined $message) {
		$@ = "No message provided for the e-mail.";
		return undef;
	}

	# Try to send the mail.
	if ($self->{method} eq "smtp") {
		use Mail::Sendmail;
		my $smtp = {
			'Content-type' => 'text/plain; charset="utf-8"',
			Smtp => Siikir::Util::stripSimple($self->{server}),
			Port => Siikir::Util::stripSimple($self->{port}),
			From => Siikir::Util::stripSimple($self->{sender}),
			To   => $email,
			Subject => $subject,
			Message => $message,
		};
		if (defined $replyto) {
			$smtp->{'Reply-To'} = $replyto;
		}

		# Encode to bytes?
		$smtp = Siikir::Util::utf8_encode($smtp);
		Mail::Sendmail::sendmail(%{$smtp});
	}
	elsif ($self->{method} eq "sendmail") {
		# Untaint the sendmail program. We trust the admin.
		my ($cmd) = ($self->{command} =~ /^(.+?)$/);
		return undef unless $cmd;

		# Secure the PATH.
		local $ENV{PATH} = "/usr/bin:/bin:/usr/sbin:/sbin";

		my $headers = "Content-Type: text/plain\n";
		if (defined $replyto) {
			$headers .= "Reply-To: $replyto\n";
		}
		open (my $sm, "|-", $cmd);
		print {$sm} "From: $self->{sender}\n"
			. "To: $email\n"
			. "Subject: $subject\n"
			. "$headers\n"
			. $message;
		close ($sm);
	}
	else {
		die "Unsupported mail method $self->{method}!";
	}

	return 1;
}

=head2 int getUnread (int userid)

Get the number of unread messages for C<userid>.

=cut

sub getUnread {
	my ($self,$uid) = @_;
	$uid = Siikir::Util::stripID($uid);

	# User must exist.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "Can't get mailbox: user ID not found.";
		return undef;
	}

	my $mail = $self->getMailboxes($uid);
	my $unread = 0;
	foreach my $msg (@{$mail->{inbox}}) {
		# Skip blocked.
		if ($self->Master->User->isBlocked($uid, $msg->{from}) || $self->Master->User->isBlocked($msg->{from},$uid)) {
			next;
		}
		$unread++ unless $msg->{read};
	}

	return $unread;
}

=head2 bool sendMessage (hash options)

Send a message to a user on the site. Options include:

  int    from: user ID of the sender
  int    to:   user ID of the recipient
  string subject
  string message
  bool   html: Allow HTML to be used in the message.

Both sender and receiver must be existing users or this method fails.

=cut

sub sendMessage {
	my ($self,%opts) = @_;

	my $from = Siikir::Util::stripID($opts{from});
	my $to   = Siikir::Util::stripID($opts{to});
	my $subject = Siikir::Util::stripHTML($opts{subject}) || "[no subject]";
	my $message = $opts{html} ? $opts{message} : (Siikir::Util::stripHTML($opts{message}) || "");

	if (length $message == 0) {
		$@ = "Can't send a blank message to a user!";
		return undef;
	}
	if (!$self->Master->User->userExists(id => $from)) {
		$@ = "Sending user's ID doesn't exist.";
		return undef;
	}
	if (!$self->Master->User->userExists(id => $to)) {
		$@ = "Recipient user ID doesn't exist.";
		return undef;
	}

	# Get their mailboxes.
	my $toBox   = $self->getMailboxes($to);
	my $fromBox = $self->getMailboxes($from);

	# Add the messages.
	my $mail = {
		ip      => $ENV{REMOTE_ADDR},
		time    => time(),
		read    => 0,
		from    => $from,
		to      => $to,
		subject => $subject,
		message => $message,
	};
	unshift (@{$toBox->{inbox}},  $mail);
	unshift (@{$fromBox->{sent}}, $mail);

	# Write the mailboxes.
	$self->Master->JsonDB->writeDocument("mail/inbox/$to", $toBox->{inbox});
	$self->Master->JsonDB->writeDocument("mail/sent/$from", $fromBox->{sent});
	my $sender = $self->Master->Profile->getProfile($from);
	my $recip  = $self->Master->Profile->getProfile($to);

	# Now always filter HTML.
	if ($opts{html}) {
		$message =~ s/<(.|\n)+?>//g;
	}

	# Send e-mail notification to the recipient.
	$self->email (
		to      => $to,
		subject => "New Siikir Message from $sender->{displayname}",
		message => "Hi $recip->{displayname},\n\n"
			. "$sender->{displayname} has just sent you a message on Siikir!\n\n"
			. "--------------\n\n"
			. "Subject: $subject\n"
			. "$message\n\n"
			. "--------------\n\n"
			. "To view your message and send a reply, visit "
			. "http://www.siikir.com/mail\n\n"
			. "Do not reply to this e-mail; it was automatically generated.",
	);

	return 1;
}

=head2 hash getMailboxes (int userid)

Return a hash of the mailboxes of a user. Returns keys "inbox" and
"outbox".

=cut

sub getMailboxes {
	my ($self,$uid) = @_;
	$uid = Siikir::Util::stripID($uid);

	# User must exist.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "Can't get mailbox: user ID not found.";
		return undef;
	}

	my $inbox = [];
	my $sent  = [];
	if ($self->Master->JsonDB->documentExists("mail/inbox/$uid")) {
		$inbox = $self->Master->JsonDB->getDocument("mail/inbox/$uid");
	}
	if ($self->Master->JsonDB->documentExists("mail/sent/$uid")) {
		$sent = $self->Master->JsonDB->getDocument("mail/sent/$uid");
	}

	return {
		inbox => $inbox,
		sent  => $sent,
	};
}

=head2 void setMessages (int userid, string box, aref messages)

Set the entirety of the messages in a user's mailbox. This is for i.e. when a
message gets marked read.

=cut

sub setMessages {
	my ($self,$uid,$box,$messages) = @_;
	$uid = Siikir::Util::stripID($uid);
	$box = Siikir::Util::stripPaths($box);

	# User must exist.
	if (!$self->Master->User->userExists(id => $uid)) {
		$@ = "Can't get mailbox: user ID not found.";
		return undef;
	}

	$self->Master->JsonDB->writeDocument("mail/$box/$uid", $messages);
	return 1;
}

1;
