package PhaidraAPI::Controller::Iiifmanifest;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use PhaidraAPI::Model::Iiifmanifest;
use Mojo::ByteStream qw(b);
use Mojo::JSON qw(encode_json decode_json);
use Time::HiRes qw/tv_interval gettimeofday/;

sub update_manifest_metadata {
  my $self = shift;

  my $res = {alerts => [], status => 200};

  my $pid = $self->stash('pid');

  my $iiifm_model = PhaidraAPI::Model::Iiifmanifest->new;
  my $r           = $iiifm_model->update_manifest_metadata($self, $pid);
  if ($r->{status} ne 200) {

    # just log but don't change status, this isn't fatal
    push @{$res->{alerts}}, {type => 'danger', msg => 'Error updating IIIF-MANIFEST metadata'};
    push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
  }

  $self->render(json => $res, status => $res->{status});
}

sub post {
  my $self = shift;

  my $t0 = [gettimeofday];

  my $pid = $self->stash('pid');

  my $metadata = $self->param('metadata');
  unless (defined($metadata)) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'No metadata sent'}]}, status => 400);
    return;
  }

  eval {
    if (ref $metadata eq 'Mojo::Upload') {
      $self->app->log->debug("Metadata sent as file param");
      $metadata = $metadata->asset->slurp;
      $self->app->log->debug("parsing json");
      $metadata = decode_json($metadata);
    }
    else {
      # http://showmetheco.de/articles/2010/10/how-to-avoid-unicode-pitfalls-in-mojolicious.html
      $self->app->log->debug("parsing json");
      $metadata = decode_json(b($metadata)->encode('UTF-8'));
    }
  };

  if ($@) {
    $self->app->log->error("Error: $@");
    $self->render(json => {alerts => [{type => 'danger', msg => $@}]}, status => 400);
    return;
  }

  unless (defined($metadata->{metadata})) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'No metadata found'}]}, status => 400);
    return;
  }
  $metadata = $metadata->{metadata};

  unless (defined($pid)) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'Undefined pid'}]}, status => 400);
    return;
  }

  unless (defined($metadata->{'iiif-manifest'}) || defined($metadata->{'IIIF-MANIFEST'})) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'No IIIF-MANIFEST sent'}]}, status => 400);
    return;
  }

  my $manifest;
  if (defined($metadata->{'iiif-manifest'})) {
    $manifest = $metadata->{'iiif-manifest'};
  }
  else {
    $manifest = $metadata->{'IIIF-MANIFEST'};
  }

  my $iiif_model = PhaidraAPI::Model::Iiifmanifest->new;
  my $res        = $iiif_model->save_to_object($self, $pid, $manifest, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

  my $t1 = tv_interval($t0);
  if ($res->{status} eq 200) {
    unshift @{$res->{alerts}}, {type => 'success', msg => "IIIF-MANIFEST for $pid saved successfully ($t1 s)"};
  }

  $self->render(json => {alerts => $res->{alerts}}, status => $res->{status});
}

1;
