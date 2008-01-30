
# Test Includes
# $Id: include.t,v 1.1 2007/10/05 13:55:48 gellyfish Exp $

use strict;

use Test::More tests => 2;

use vars qw($DEBUGGING);

$DEBUGGING = 0;

use_ok('XML::XSLT');


my $xml =<<'EOX';
<doc>
   <bar />
</doc>
EOX

my $stylesheet =<<'EOS';
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="xml"/>
<xsl:include href="t/include.xsl"/> 
<xsl:template match="/">
        <xsl:call-template name="included" />

</xsl:template>
</xsl:stylesheet>
EOS

my $expect = '<foo>bar</foo>';


my $parser = XML::XSLT->new(\$stylesheet,debug => $DEBUGGING);
$parser->transform(\$xml);
my $out = $parser->toString();

ok($out eq $expect,'pattern template selector');
