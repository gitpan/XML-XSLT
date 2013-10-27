# note that the use of select="*|text()" works fine in sabletron
# and libXSLT, but fails, returning an empty tag, in XML::XSLT

use Test::More tests => 3;

my $xml = <<EOXML;
<story>
   Text outside markup
   <p>
      Text inside markup
   </p>
</story>
EOXML

my $xsl = <<EOXSL;
<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/ 
              Transform">

<xsl:output method="xml" indent="yes" encoding="UTF-8" />

<xsl:template match="story">
   <nitf>
      <xsl:copy-of select="*|text()"/>
   </nitf>
</xsl:template>

</xsl:stylesheet>
EOXSL

use XML::XSLT qw(serve);

my $xslt = XML::XSLT->new($xsl);
my $result = $xslt->serve(\$xml);
like($result, qr/Text outside/, "got text outside markup");
like($result, qr/Text inside/, "got text inside markup");
unlike($result, qr(<nitf/>), "didn't get empty tag");
                         
