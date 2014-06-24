package Siikir 2012.1114;

use 5.14.0;
use strict;
use warnings;
use Siikir::Util;
use Carp;

our $AUTOLOAD;
our $singleton;

=head1 NAME

Siikir - Content management system for Siikir.com.

=head1 SYNOPSIS

  use Siikir;
  my $cms = Siikir->new->run();

=head1 METHODS

=head2 Siikir new (hash options)

Options include:

  bool debug:  Debug mode (writes to STDERR)
  str  root:   Root of private CMS files (default "./cms")
  obj  cgi:    A CGI object if you already have one.

=cut

sub new {
	my $package = shift;
	my $class   = ref($package) || $package;
	my %opts    = @_;

	my $self = {
		# User provided options.
		debug => $opts{debug} || 0,
		root  => $opts{root} || "./cms",
		cgi   => $opts{cgi} || undef,

		# Internal data.
		plugins => {}, # Plugin objects
		queue   => {}, # Queue of plugins to load (for plugin inter-dependency)
	};

	bless ($self,$class);
	$singleton = $self;
	return $self;
}

sub debug {
	my ($self,$line) = @_;
	return unless $self->{debug};

	# Print to error log.
	print STDERR "SIIKIR: $line\n";

	# Print to debug log (slow!)
	open (my $log, ">>", "debug.log");
	print {$log} "[" . scalar(localtime()) . "] $line\n";
	close ($log);
}

sub fatal {
	my ($self,$err) = @_;
	confess $err;
}

=head2 Plugin loadPlugin ()

Load a CMS plugin into memory. Returns a reference to the newly
loaded plugin, if you want it.

=cut

sub loadPlugin {
	my ($self,$plugin) = @_;
	$plugin = Siikir::Util::stripPaths($plugin);

	# Don't load it twice.
	if (exists $self->{plugins}->{$plugin}) {
		return $self->{plugins}->{$plugin};
	}

	# Initialize the plugin.
	my $file = "$self->{root}/plugins/$plugin.pm";
	my $ns   = "Siikir::Plugin::$plugin";

	# Include and initialize it.
	require $file;
	$self->{plugins}->{$plugin} = $ns->new (
		_name  => $plugin,
		debug  => $self->{debug},
		root   => $self->{root},
		#parent => $self,
	);

	# Get the plugin's requirements.
	my @req = $self->{plugins}->{$plugin}->getRequirements();
	foreach my $plug (@req) {
		if (!exists $self->{plugins}->{$plug}) {
			$self->loadPlugin($plug);
		}
	}

	return $self->{plugins}->{$plugin};
}

=head2 Plugin plugin (String name)

Retreive the instance of the plugin named C<name>.

=cut

sub plugin {
	my ($self,$name) = @_;
	if (exists $self->{plugins}->{$name}) {
		return $self->{plugins}->{$name};
	}

	confess "Plugin $name not loaded!";
}

=head2 aref listAvailablePlugins ()

Retrieve a list of all available plugins from the C<plugins> folder.

=cut

sub listAvailablePlugins {
	my $self = shift;

	my $plugins = [];

	opendir (DIR, "$self->{root}/plugins") or die "Can't read plugin folder: $@";
	foreach my $pm (sort(grep(/\.pm$/i, readdir(DIR)))) {
		$pm =~ s/\.pm$//i;
		push (@{$plugins}, $pm);
	}
	closedir (DIR);

	return $plugins;
}

sub AUTOLOAD {
	my $self = shift;
	my $name = $AUTOLOAD;
	$name =~ s/^.*:://; # Strip fully qualified portion
	return $self->plugin($name);
}

sub DESTROY {
	my $self = shift;

	# Destroy all the plugins to clean up memory leaks.
	foreach my $plugin (keys %{$self->{plugins}}) {
		delete $self->{plugins}->{$plugin};
	}
}

1;
