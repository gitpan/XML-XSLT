# Test that attributes work
# $Id: attributes.t,v 1.3 2002/01/09 09:17:40 gellyfish Exp $

use Test::More tests => 4;

use strict;
use vars qw($DEBUGGING);

$DEBUGGING = 0;

use_ok('XML::XSLT');

eval
{
   my $stylesheet = <<EOS;
<?xml version="1.0"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:template match="doc"><doc><xsl:apply-templates/></doc></xsl:template>
<xsl:template match="p">
<p><xsl:attribute name="test"><xsl:text>foo</xsl:text></xsl:attribute><xsl:text>Foo</xsl:text></p>
</xsl:template>
</xsl:stylesheet>
EOS

   my $xml =<<EOX;
<?xml version="1.0"?>
<doc><p>Some Random text</p></doc>
EOX

   my $expected = qq{<doc><p test="foo">Foo</p></doc>};
   my $parser = XML::XSLT->new(\$stylesheet,debug => $DEBUGGING);

   $parser->transform(\$xml);

   my $outstr = $parser->toString();

   warn "$outstr\n" if $DEBUGGING;

    $parser->dispose();

   die "$outstr ne $expected\n" unless $outstr eq $expected;
};

ok(!$@, "xsl:attribute works");

eval
{
   my $stylesheet =<<EOS;
<?xml version="1.0"?>
<xsl:transform xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
               version="1.0">

  <xsl:output method="xml"
       encoding="ISO-8859-1"
       indent="yes"/>

  <xsl:attribute-set name="outer-table">
     <xsl:attribute name="summary">
        <xsl:text>This is a summary</xsl:text>
     </xsl:attribute>
  </xsl:attribute-set>
  <xsl:template match="doc"><doc><xsl:apply-templates /></doc></xsl:template>

  <xsl:template match="p">
    <xsl:element name="p" use-attribute-sets="outer-table">
       <xsl:text>Foo</xsl:text>
    </xsl:element>
</xsl:template>
</xsl:transform>
EOS

  my $xml =<<EOX;
<?xml version="1.0"?>
<doc><p>Some Random text</p></doc>
EOX

  my $parser = XML::XSLT->new(\$stylesheet,debug => $DEBUGGING);

  $parser->transform(\$xml);

  
  my $outstr =  $parser->toString() ;

  my $expected =<<EOE;
<doc><p summary="This is a summary">Foo</p></doc>
EOE

  chomp($expected);

  warn "$outstr\n" if $DEBUGGING;
  die "$outstr ne $expected\n" unless $outstr eq $expected;

  $parser->dispose();
};

warn "$@\n" if $DEBUGGING;

ok(!$@, "attribute-set in element");

eval
{
   my $stylesheet =<<EOS;
<xsl:stylesheet
  version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:axsl="http://www.w3.org/1999/XSL/TransformAlias">

<xsl:template match="doc">
<doc>
<xsl:attribute name="xmlns:xsl" namespace="whatever">http://www.w3.org/1999/XSL/Transform</xsl:attribute>
<xsl:attribute name="attr">value</xsl:attribute>
</doc>
</xsl:template>

</xsl:stylesheet>
EOS

  my $xml = '<doc/>';

  my $parser = XML::XSLT->new(\$stylesheet,debug => $DEBUGGING);

  $parser->transform(\$xml);

  
  my $outstr =  $parser->toString() ;



  warn "$outstr\n" if $DEBUGGING;
  die "$outstr contains xmlns declaration\n" if $outstr =~ /xmlns:xsl/ ;

  $parser->dispose();

};

warn "$@\n" if $DEBUGGING;

ok(!$@, "do not output namespace declaration");
