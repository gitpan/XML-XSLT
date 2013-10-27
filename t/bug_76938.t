
use strict;
use warnings;

use Test::More tests => 1;                      # last test to print

use XML::XSLT;

my $xsl='
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:template match="/">
<ul>
<li>1 :<xsl:value-of select="uppernode/mynode[@num=1]"/></li>
<li>2 :<xsl:value-of select="uppernode/mynode[@num=2]"/></li>
<li>3 :<xsl:value-of select="uppernode/mynode[@num=3]"/></li>
</ul>
</xsl:template>
</xsl:stylesheet>
';

my $xml="<?xml version='1.0'?>
<uppernode>
<mynode num='1'>This is one</mynode>
<mynode num='2'>This is two</mynode>
<mynode num='3'>This is three</mynode>
</uppernode>
";

my $debug = 0;

my $xslt = XML::XSLT->new($xsl, warnings => 1, debug => $debug);
$xslt->transform($xml);
ok($xslt->toString() =~ /.*This is one.*This is two.*This is three.*/, "got the right child nodes by attribute index");


