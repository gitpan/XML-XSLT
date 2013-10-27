use Test::More tests => 2;

my $xml = <<EOXML;
<content>
  Text outside markup
  <p>Text inside markup</p>
</content>
EOXML

my $xsl = <<EOXSL;
<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

<xsl:output method="xml" indent="yes" encoding="UTF-8" />

<xsl:template match="/">
        <content>
                <xsl:apply-templates/>
        </content>
</xsl:template>
<xsl:template match="a|ul|ol|il|li|sub|sup|q|table|td|tr|th|thead|tfoot|tbody|colgroup|col|hr|p"> 
        <xsl:copy-of select="current()"/>
</xsl:template>
</xsl:stylesheet>
EOXSL

use XML::XSLT qw(serve);

$xslt = XML::XSLT->new($xsl,debug => 0);
my $result = $xslt->transform($xml)->toString;

like($result, qr/Text outside/, "got text outside markup");
like($result, qr/<p>Text inside/, "got text inside markup");
