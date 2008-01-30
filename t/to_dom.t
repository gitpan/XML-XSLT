# Test that to_dom() works
# $Id: to_dom.t,v 1.1 2007/10/05 13:44:04 gellyfish Exp $

use strict;

use Test::More tests => 2;

use vars qw($DEBUGGING);

$DEBUGGING = 0;

use_ok('XML::XSLT');

my $output;
eval
{
  my $stylesheet =<<EOS;
<?xml version="1.0"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:template match="doc"><doc><xsl:comment>Comment</xsl:comment></doc></xsl:template>
</xsl:stylesheet>
EOS

  my $xml =<<EOX;
<?xml version="1.0"?>
<doc>Foo</doc>  
EOX

  my $parser = XML::XSLT->new(\$stylesheet,debug => $DEBUGGING);

  $parser->transform(\$xml);

  $output =  ref $parser->to_dom();

  die $output unless $output =~ /^XML::DOM::Document$/;
};

ok(!$@,"Outputs an XML::DOM::Document");
