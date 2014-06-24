package Siikir::Plugin::JsonDB 2012.1114;

use 5.14.0;
use strict;
use warnings;
use JSON;
use CGI::Carp qw(fatalsToBrowser);
use Siikir::Util;
use utf8;

use base "Siikir::Plugin";

=head1 NAME

Siikir::Plugin::JsonDB - A flat JSON document database system.

=cut

sub init {
	my $self = shift;

	$self->debug("JsonDb plugin loaded!");

	# Initialize JSON.
	$self->{json} = JSON->new->pretty();

	# Cache documents for this session. Only delete cached
	# documents when new documents are written.
	$self->{cache} = {};

	# Keep singleton.
	$Siikir::Plugin::JsonDB::SINGLETON = $self;
}

=head1 METHODS

=head2 data getDocument (string path[, bool nocache])

Retrieve a JSON document located at C<path>, relative to C<root/db>. Don't
include the file extension. For example, "C<users/kirsle>".

Returns undef if the document couldn't be read.

By default, the document is cached in memory to speed up future requests
for the same document. To suppress caching, provide a true value for the
C<nocache> field.

=cut

sub getDocument {
	my ($self,$path) = @_;

	$self->debug("Trying to fetch JSON document: $path");

	# If the cache exists...
	if (exists $self->{cache}->{$path}) {
		# Check if the cache is fresh.
		my ($mtime) = (stat("$self->{root}/db/$path.json"))[9];
		if ($mtime > $self->{cache}->{$path}->{mtime}) {
			delete $self->{cache}->{$path};
		}
		else {
			return Siikir::Util::clone($self->{cache}->{$path}->{data});
		}
	}

	# Exists?
	if (!$self->documentExists($path)) {
		$@ = "Document '$path' doesn't exist.";
		return undef;
	}

	# Return the JSON decoded output.
	my $doc = "$self->{root}/db/$path.json";
	my $data = $self->readJSON($doc);

	# Cache and return it.
	$self->{cache}->{$path}->{mtime} = (stat("$self->{root}/db/$path.json"))[9];
	$self->{cache}->{$path}->{data}  = $data;

	# Return a clone of the data so the user can't modify the cached document.
	return Siikir::Util::clone($data);
}

=head2 bool documentExists (path)

Query whether a document exists.

=cut

sub documentExists {
	my ($self,$path) = @_;

	$self->debug("Check exists JSON document: $path");

	my $doc = "$self->{root}/db/$path.json";
	if (-f $doc) {
		return 1;
	}

	return undef;
}

=head2 void writeDocument (path, data)

Write a document to disk.

=cut

sub writeDocument {
	my ($self,$path,$data) = @_;

	$self->debug("Write to JSON document: $path");

	# Need to create the file?
	my $doc = "$self->{root}/db/$path";
	if (!-f $doc) {
		$self->debug("Document $doc doesn't exist yet, resolving its path...");

		# The doc may contain a folder and filename.
		if ($path =~ /\//) {
			my @parts = split(/\//, $path);
			pop(@parts); # Drop the file name
			$self->debug("parts: @parts");
			my @dir = ();
			foreach my $p (@parts) {
				push (@dir, $p);
				my $segment = join("/", @dir);
				$self->debug("Making sure $segment exists...");
				if (!-d "$self->{root}/db/$segment") {
					mkdir("$self->{root}/db/$segment");
				}
			}
		}
	}

	# Delete the cache. This will guarantee a fresh cache next time.
	delete $self->{cache}->{$path};

	# Write the JSON.
	$self->writeJSON("$doc.json", $data);
}

=head2 array listDocuments (path)

List all the documents in a folder relative to db.

=cut

sub listDocuments {
	my ($self,$path) = @_;

	return () unless -d "$self->{root}/db/$path";

	my @docs;
	opendir (DIR, "$self->{root}/db/$path");
	foreach my $file (sort(grep(/\.json$/i, readdir(DIR)))) {
		my $doc = $file;
		$doc =~ s/\.json$//i;
		push (@docs, Siikir::Util::stripPaths($doc));
	}
	closedir (DIR);

	return @docs;
}

=head2 void deleteDocument (path)

Delete a document from a database folder.

=cut

sub deleteDocument {
	my ($self,$path) = @_;

	my $doc = "$self->{root}/db/$path.json";
	if (-f $doc) {
		unlink($doc);
	}

	# Delete the cache.
	delete $self->{cache}->{$path};
}

=head2 private data readJSON (path.json)

Slurps, decodes and returns data from a JSON document. Errors are fatal.

=cut

sub readJSON {
	my ($self,$path) = @_;

	# Must exist.
	if (!-f $path) {
		$self->Master->fatal("Can't read JSON file $path: not found!");
	}

	# Slurp it.
	$self->lock($path);
	open (my $fh, "<:utf8", $path);
	local $/;
	my $data = <$fh>;
	close ($fh);
	$self->unlock($path);

	# Decode it.
	my $decoded;
	eval {
		$decoded = $self->{json}->decode($data);
	};
	if ($@) {
		warn "Couldn't decode JSON from $path: $@ (self: $self; single: $Siikir::Plugin::JsonDB::SINGLETON)";
		return undef;
	}

	return $decoded;
}

=head2 private void writeJSON (path.json, data)

Write a JSON document.

=cut

sub writeJSON {
	my ($self,$path,$data) = @_;

	# Write.
	$self->lock($path);
	eval {
		open (my $fh, ">:utf8", $path) or $self->Master->fatal("Can't write JSON to $path: $@");
		print {$fh} $self->{json}->encode($data);
		close ($fh);
	};
	$self->unlock($path);
	if ($@) {
		die "$@ " . Dumper($data); use Data::Dumper;
	}
}

=head2 private void lock (path)

Lock a file with a lockfile.

=cut

sub lock {
	my ($self,$file) = @_;
	my $lock = "$file.lck";

	# Lock exists already?
	my $i = 0;
	while (-f $lock) {
		$i++;
		sleep(1);
		if ($i == 10) {
			# Just steal it.
			warn "Waited 10 seconds to steal lock on $file!";
			last;
		}
	}

	# Write the lock.
	open (my $fh, ">", $lock);
	print {$fh} $$;
	close ($fh);
}

=head2 private void unlock (path)

Unlock a file.

=cut

sub unlock {
	my ($self,$file) = @_;
	my $lock = "$file.lck";

	if (-f $lock) {
		unlink($lock);
	}
}

1;
