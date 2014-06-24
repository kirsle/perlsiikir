package Siikir::Plugin 1.20110521;

use 5.14.0;
use strict;
use warnings;

our $VERSION = '1.00';
our $SINGLETON = undef;

=head1 NAME

Siikir::Plugin - Base class for Siikir plugins.

=head1 SYNOPSIS

  package Siikir::Plugin::MyPlugin;
  use base "Siikir::Plugin";

=head1 METHODS

=head2 Siikir new (hash options)

Don't override this. Override C<init()> instead.

=cut

sub new {
	my $package = shift;
	my $class   = ref($package) || $package;
	my %opts    = @_;

	# Allow plugins to be singletons if they want.
	if (defined $SINGLETON) {
		return $SINGLETON;
	}

	my $self = {
		# Parent provided options.
		debug      => $opts{debug}  || 0,
		root       => $opts{root}   || "./cms",
		#parent     => $opts{parent} || undef,
		_name      => $opts{_name}  || $package,
		_interface => undef,
	};

	bless ($self,$class);
	$self->requires("JsonDB");
	$self->init();
	return $self;
}

=head2 void init ()

Called one time when the plugin is initialized. This is where the
plugin should load its configuration.

=cut

sub init {}

=head2 Siikir Master ()

Get a reference to the parent Siikir object, so you can manipulate
other objects for example.

=cut

sub Master {
	my $self = shift;
	return $Siikir::singleton; #$self->{parent};
}

=head2 void debug (string)

Shortcut to Siikir's debug().

=cut

sub debug {
	my $self = shift;
	return $self->Master->debug(@_);
}

=head2 void requires (array)

List one or more plugins that your plugin requires to function properly.

=cut

sub requires {
	my ($self,@requires) = @_;
	if (!exists $self->{_requires}) {
		$self->{_requires} = [];
	}
	push @{$self->{_requires}}, @requires;
}

=head2 array getRequirements ()

Retrieve the list of plugins a plugin requires.

=cut

sub getRequirements {
	my $self = shift;
	return exists $self->{_requires} ? @{$self->{_requires}} : ();
}

=head2 hash options (hash options)

Declare the default configuration for your plugin. If a config file exists
for the plugin, its data will be returned; otherwise the default will.

=cut

sub options {
	my ($self,%opts) = @_;

	# Set the defaults first.
	foreach my $key (keys %opts) {
		$self->{$key} = $opts{$key};
	}

	# If there's a config file, load it.
	my $name = $self->{_name};
	return unless length $name;
	if ($self->Master->JsonDB->documentExists("config/plugins/$name")) {
		my $conf = $self->Master->JsonDB->getDocument("config/plugins/$name");
		foreach my $key (keys %{$conf}) {
			$self->{$key} = $conf->{$key};
		}
	}
}

=head2 void setOptions (hash options)

Override (to re-define) options for the plugin. This sets the options in memory
but does NOT also load options from disk. It should only be used in the admin
plugin configurator page to override options before saving them to disk.

=cut

sub setOptions {
	my ($self,%opts) = @_;

	# Set the options.
	foreach my $key (keys %opts) {
		$self->{$key} = $opts{$key};
	}
}

=head2 bool saveOptions ()

Dump the options to disk.

=cut

sub saveOptions {
	my $self = shift;

	# Get the plugin's name.
	my $name = $self->{_name};
	return unless length $name;

	# Prepare the options for saving.
	my $save = {};
	foreach my $opt (keys %{$self}) {
		next if $opt =~ /^_/;                    # Skip private options
		next if $opt =~ /^(debug|root|parent)$/; # Skip private options
		$save->{$opt} = $self->{$opt};
	}

	# Save.
	return $self->Master->JsonDB->writeDocument("config/plugins/$name", $save);
}

=head2 aref interface (aref interface)

Define (or get) an "interface" descriptor for modifying the options for the
plugin.

=cut

sub interface {
	my ($self,$interface) = @_;

	if (defined $interface) {
		$self->{_interface} = $interface;
	}

	return $self->{_interface};
}

1;
