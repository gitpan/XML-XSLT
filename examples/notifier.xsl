<xsl:stylesheet xmlns:xsl="http://www.w3.org/TR/WD-xsl">

<xsl:template><xsl:apply-templates/></xsl:template>

<xsl:template match="text()"><xsl:value-of select="."/></xsl:template>

<xsl:template match="text()|@*"><xsl:value-of select="."/></xsl:template>

<xsl:template match="/"><html>
<BODY>
<TABLE height="100%" width="100%">
  <TBODY>
  <TR>
    <TD align="middle" class="outer"><LINK href="../jupiter.css" rel="stylesheet" title="new" type="text/css">
      <TABLE border="1" class="table" width="550">
        <COLGROUP>
        <COL id="col1">
        <COL id="col2">
        <TBODY>
        <TR>
          <FONT size="+2">
            <xsl:apply-templates/>
				
				</FONT></TR></TBODY></COL></COL></COLGROUP></TABLE></LINK></TD></TR></TBODY></TABLE></BODY>
				
		</html>		</xsl:template>

<xsl:template match="NAME"><b><font size="3" color="blue"><xsl:apply-templates/></font></b></xsl:template>

<xsl:template match="BODY"><xsl:apply-templates/></xsl:template>

<xsl:template match="EMAIL" mode="display"><font size="3"><xsl:apply-templates/></font></xsl:template>

<xsl:template match="EMAIL_STATS"><td colspan="2"><font color="blue">Email Notification Server:</font><xsl:apply-templates select="TYPE" /><font color="blue">ORDER:</font><xsl:apply-templates select="ORDER" /></td>
<tr><td>Agent:</td><td><xsl:apply-templates select="NAME"/></td></tr>
<tr><td>Phone:</td><td><xsl:apply-templates select="PHONE"/></td></tr>
<tr><td>MLS:</td><td><xsl:apply-templates select="MLS"/></td></tr>
<tr><td>Adddr:</td><td><xsl:apply-templates select="ADDY"/></td></tr>
<tr><td>Posting Sites:</td><td><xsl:apply-templates select="SITE"/></td></tr>
<tr><td>Scene Codes:</td><td><xsl:apply-templates select="SCENE_CODE"/></td></tr>
<tr class="spacer"><td align="middle" class="spacer" colSpan="2">********</td></tr>
<tr><td>Verifier: </td><td>

  <INPUT name="VerifierEmail" size="30" value='{VERIFIER}' />
</td></tr>
<tr><td>CUSTOMER EMAIL: </td><td><xsl:apply-templates select="CUSTOMER_EMAIL"/></td></tr>
<tr><td>FROM: </td><td><xsl:apply-templates select="FROM"/></td></tr>
<tr><td>BROKERAGE EMAIL: </td><td><xsl:apply-templates select="BROKERAGE"/></td></tr>
<tr><td>PARTNER EMAIL: </td><td><xsl:apply-templates select="PARTNER"/></td></tr>
<tr><td>BAMBOO EMAIL: </td><td><xsl:apply-templates select="BAMBOO_EMAIL"/></td></tr>
<tr><td>COMPANY EMAIL: </td><td><xsl:apply-templates select="COMPANY_EMAIL"/></td></tr>
<tr><td>SUBJECT: </td><td><xsl:apply-templates select="SUBJECT"/></td></tr>
<tr><td colspan="2"><xsl:apply-templates select="BODY"/></td></tr>
<tr class="spacer"><td align="middle" class="spacer" colSpan="2">********</td></tr>
<tr><td>BSP EMAIL: </td><td><xsl:apply-templates select="BSP_EMAIL"/></td></tr>
<tr><td>BAM EMAIL: </td><td><xsl:apply-templates select="BAM_EMAIL"/></td></tr>
<tr><td>SUBJECT: </td><td><xsl:apply-templates select="BSP_SUBJECT"/></td></tr>
<tr><td colspan="2"><xsl:apply-templates select="BSP_BODY"/></td></tr></xsl:template>

<xsl:template match="EMAIL" mode="test"><xsl:apply-templates/></xsl:template>

<xsl:template match="ID"><xsl:apply-templates/></xsl:template>

<xsl:template match="VERIFIER"><xsl:apply-templates/></xsl:template>

</xsl:stylesheet>
