#!/usr/bin/env perl

use strict;
use warnings;
use Apache2::ServerUtil ();

BEGIN {
  return unless Apache2::ServerUtil::restart_count() > 1;

  # require lib;
  # lib->import('/path/to/my/perl/libs');

  require Plack::Handler::Apache2;

  my @psgis = ('/usr/local/phaidra/phaidra-api/phaidra-api.cgi');
  foreach my $psgi (@psgis) {
    Plack::Handler::Apache2->preload($psgi);
  }
}

1;
