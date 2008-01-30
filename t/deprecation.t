#!/usr/nin/perl
# Test deprecation
# $Id: deprecation.t,v 1.1 2008/01/30 11:23:54 gellyfish Exp $

use strict;

use Test::More tests => 3;

use vars qw($DEBUGGING);

$DEBUGGING = 0;

use_ok('XML::XSLT');

my $foo;

local $SIG{__WARN__} = sub {  ($foo) = @_; };

eval
{

  my $parser = XML::XSLT->new(debug => $DEBUGGING);
};

ok($foo =~ /new deprecated/, "warns about deprecation");

eval
{
    $foo = undef;
    my $parser = XML::XSLT->new(use_deprecated => 1,debug => $DEBUGGING);
};

ok(!$foo,"switch deprecations off");
