package Siikir::Controller::admin::index;

use strict;
use Siikir::Util;

sub process {
	my ($self, $vars, $url) = @_;

	# We need the Profile plugin.
	$self->Master->loadPlugin("User");
	$self->Master->loadPlugin("Profile");
	$self->Master->loadPlugin("Photo");
	$self->Master->loadPlugin("Messaging");

	# Must be logged in.
	if (!$vars->{login}) {
		$self->Master->CGI->redirect("/account/login?return=/admin");
		return $vars;
	}
	elsif (!$vars->{isAdmin}) {
		$self->Master->CGI->redirect("/");
		return $vars;
	}

	my $action = scalar @{$url} ? $url->[0] : "index";
	$vars->{action} = $action;

	# Admin actions.
	if ($action eq "approval") {
		# Are we judging a photo?
		my $judgment = $vars->{param}->{judgment} || '';
		if ($judgment eq "approve" || $judgment eq "deny") {
			# Let the photo plugin deal with it.
			my $result = $self->Master->Photo->judgeReport (
				judgment => $vars->{param}->{judgment},
				owner    => $vars->{param}->{uid},
				photo    => $vars->{param}->{photo},
			);
			if (!defined $result) {
				$vars->{errors} = [ "Failed to judge photo: $@" ];
				return $vars;
			}
			$vars->{success} = $result;
		}

		# Pending photo approval.
		my $pending = $self->Master->Photo->getReports(1);
		$vars->{reports} = $pending;
	}
	elsif ($action eq "config") {
		my $sub = scalar @{$url} > 1 ? $url->[1] : "index";
		$vars->{sub} = $sub;

		# Editing a plugin?
		if ($sub eq "edit") {
			# Load this plugin and get its interface.
			my $plugin = $vars->{param}->{plugin};
			$self->Master->loadPlugin($plugin);
			$vars->{plugin} = $plugin;
			$vars->{fields} = $self->Master->plugin($plugin)->interface();
			$vars->{values} = $self->Master->plugin($plugin);
			if (!defined $vars->{fields}) {
				return $self->showError($vars, "This plugin doesn't have a configurable interface.");
			}
		}
		elsif ($sub eq "save") {
			# Load this plugin and get its interface.
			my $plugin = $vars->{param}->{plugin};
			$self->Master->loadPlugin($plugin);
			$vars->{plugin} = $plugin;
			my $interface   = $self->Master->plugin($plugin)->interface();
			if (!defined $interface) {
				return $self->showError($vars, "This plugin doesn't have a configurable interface.");
			}

			# Process the form fields.
			my $result = Siikir::Util::paramFields ($interface, $vars->{param}, allowhtml => 1);

			# No errors?
			if (scalar @{$result->{errors}} == 0) {
				# Update the config and save.
				$self->Master->plugin($plugin)->setOptions (%{$result->{fields}});
				$self->Master->plugin($plugin)->saveOptions();
				$vars->{success} = 1;
			}

			$vars->{errors} = $result->{errors};
			$vars->{warnings} = $result->{warnings};
		}
		else {
			# List all plugins and interfaces.
			my $plugins = $self->Master->listAvailablePlugins();
			$vars->{plugins} = [];
			foreach my $plugin (@{$plugins}) {
				# Load the plugin and get its interface.
				$self->Master->loadPlugin($plugin);
				my $if = $self->Master->plugin($plugin)->interface();
				push (@{$vars->{plugins}}, [
					$plugin,
					defined $if ? 1 : 0
				]);
			}
		}
	}
	elsif ($action eq "users") {
		my $sub = scalar @{$url} > 1 ? $url->[1] : "index";
		$vars->{sub} = $sub;
		$vars->{photopub} = $self->Master->Photo->http();
		if ($sub eq "manage") {
			# Managing users.
			my $users = $self->Master->User->listUsers();
			$vars->{users} = [];
			foreach my $user (@{$users}) {
				my $data = {
					id => $user,
				};
				$data->{admin} = $self->Master->User->isAdmin($user);
				if ($vars->{param}->{admins} && !$data->{admin}) {
					next;
				}
				my $acct  = $self->Master->User->getAccount($user);
				next if $acct->{level} eq "deleted"; # Skip deleted users.
				my $pro   = $self->Master->Profile->getProfile($user);
				my $photo = $self->Master->Photo->getProfilePhoto($user);
				$data->{account} = $acct;
				$data->{profile} = $pro;
				$data->{photo}   = $photo;
				push (@{$vars->{users}}, $data);
			}
		}
		elsif ($sub eq "passwd") {
			# Reset a user's passwd.
			my $id = $vars->{param}->{id};
			if (!$self->Master->User->userExists(id => $id)) {
				return $self->showError($vars, "User ID not found!");
			}

			$vars->{user} = $self->Master->User->getAccount($id);
			$vars->{user}->{profile} = $self->Master->Profile->getProfile($id);
			if ($vars->{param}->{go} eq "yes") {
				my $pass = $vars->{param}->{password};
				$self->Master->User->changePassword($id, $pass);
			}
		}
		elsif ($sub eq "become") {
			# Auto login as another user.
			my $id = $vars->{param}->{id};
			if (!$self->Master->User->userExists(id => $id)) {
				return $self->showError($vars, "User ID not found!");
			}

			# Log in.
			$self->Master->User->become($id);
			$vars->{login} = 1;
			$vars->{uid}   = $id;
			$vars->{account} = $self->Master->User->getAccount($id);
			$vars->{account}->{profile} = $self->Master->Profile->getProfile($id);
			$vars->{unreadmsg} = $self->Master->Messaging->getUnread($id);
			$vars->{isAdmin}   = $self->Master->User->isAdmin($id);
		}
		elsif ($sub eq "delete") {
			# Deleting a user.
			my $id = $vars->{param}->{id};
			$vars->{user} = $self->Master->User->getAccount($id);
			$vars->{user}->{profile} = $self->Master->Profile->getProfile($id);

			# Confirm deletion?
			if ($vars->{param}->{go} eq "yes") {
				my $pass = $vars->{param}->{password};

				# The admin password is needed.
				if (!defined $self->Master->User->login($vars->{account}->{username}, $pass)) {
					$vars->{errors} = [ "You did not enter the correct password." ];
				}
				else {
					# Delete the user.
					$self->Master->User->removeUser($id);
					$vars->{success} = 1;
				}
			}
		}
	}
	elsif ($action eq "maint") {
		my $sub = scalar @{$url} > 1 ? $url->[1] : "index";
		$vars->{sub} = $sub;

		if ($sub eq "cache") {
			# Rebuilding the search cache.
			$self->Master->loadPlugin("Search");
			$self->Master->Search->buildCache();
			$vars->{action} = "index";
			$vars->{warnings} = [ "The search cache has been rebuilt." ];
		}
	}

	return $vars;
}

1;
