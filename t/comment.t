# Test that xsl:comment works
# $Id: comment.t,v 1.1 2001/12/17 11:32:08 gellyfish Exp $

use strict;

use Test::More tests => 2;

use vars qw($DEBUGGING);

$DEBUGGING = 0;

use_ok('XML::XSLT');

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

  my $wanted = '<doc><!--Comment--></doc>';
  my $outstr =  $parser->toString;
  die "$outstr ne $wanted\n" unless $outstr eq $wanted;
};

ok(!$@,"Comment text as expected");
