package Siikir::Controller::photos::upload;

use strict;
use Siikir::Util;

sub process {
	my ($self, $vars, $url) = @_;

	# We need the Photo plugin.
	$self->Master->loadPlugin("Photo");
	$vars->{photopub} = $self->Master->Photo->http();
	$vars->{adultallowed} = $self->Master->Photo->adultAllowed();

	# Must be logged in.
	if (!$vars->{login}) {
		$self->Master->CGI->redirect("/account/login?return=/photos/upload");
		return $vars;
	}

	# Did they submit the form?
	my $action = scalar(@{$url}) ? $url->[0] : "index";

	# Get our list of albums.
	my $albums = $self->Master->Photo->getAlbums($vars->{uid},$vars->{uid});
	$vars->{albums} = [ "Photos" ];
	if (defined $albums) {
		$vars->{albums} = [ map { $_->{name} } @{$albums} ];
	}

	# What was their action?
	if ($action eq "go") {
		# They're submitting the photo upload form!
		my $location = $vars->{param}->{location} || "";
		my $album    = $vars->{param}->{album} || "Photos";
		my $newAlbum = $vars->{param}->{'new-album'} || "";
		my $caption  = $vars->{param}->{caption} || "";
		my $private  = $vars->{param}->{private} eq "true" ? 1 : 0;
		my $adult    = $vars->{param}->{adult} eq "true" ? 1 : 0;

		# Any errors to give?
		my @errors = ();
		if (length $location == 0) {
			push (@errors, "No photo location specified.");
		}
		elsif ($location !~ /^(pc|www|base64)$/) {
			push (@errors, "Invalid photo location specified.");
		}
		else {
			# Handle the different photo sources.
			my @source = ();
			if ($location eq "pc") {
				push (@source,
					filename => $vars->{param}->{photo},
					handle   => $self->Master->CGI->upload("photo")
				);
			}
			elsif ($location eq "www") {
				push (@source,
					filename => $vars->{param}->{url},
					url      => $vars->{param}->{url}
				);
			}
			elsif ($location eq "base64") {
				push (@source,
					filename => $vars->{param}->{file},
					base64   => $vars->{param}->{data}
				);
			}

			# It all seems good. Attempt the upload.
			my $success = $self->Master->Photo->uploadPhoto ($vars->{uid},
				location => $location,
				@source,
				album    => length $newAlbum > 0 ? $newAlbum : $album,
				caption  => $caption,
				private  => $private,
				adult    => $adult,
			);

			if (!defined $success) {
				push (@errors, "Failed to upload photo: $@");
			}
			else {
				$vars->{success} = 1;
				$vars->{pid}     = $success; # Photo ID

				# Load this photo's data so we can show it immediately after upload.
				my $data = $self->Master->Photo->getPhoto($vars->{uid}, $success, $vars->{uid});
				if (defined $data) {
					$vars->{preview} = $data->{small};
				}
			}
		}

		$vars->{errors} = [ @errors ];
	}

	$vars->{testing} = "Action: $action";

	return $vars;
}

1;
