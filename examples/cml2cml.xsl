<?xml version="1.0"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/XSL/Transform/1.0">
  <xsl:template select="/">
    <xsl:processing-instruction name="xml">version="1.0" encoding="ISO-8859-1"</xsl:processing-instruction>
    <![CDATA[<!DOCTYPE molecule SYSTEM "http://www.xml-cml.org/cml.dtd" []>]]>
    <xsl:processing-instruction name="xml-stylesheet">type="text/xsl" href="cml.xsl"</xsl:processing-instruction>  
    <xsl:apply-templates/>
  </xsl:template>

  <xsl:template match="MOL">
    <molecule id="{@ID}" convention="DictOrgChem">
        <xsl:for-each select="XVAR">
          <xsl:choose>
	    <xsl:when test="@BUILTIN='BOILINGPOINT'">
        <float title="BoilingPoint" units="degrees Celsius"><xsl:value-of select="."/></float>
	    </xsl:when>
	    <xsl:when test="@BUILTIN='MELTINGPOINT'">
        <float title="MeltingPoint" units="degrees Celsius"><xsl:value-of select="."/></float>
	    </xsl:when>
            <xsl:when test="@BUILTIN='DENSITY'">
        <float title="Density" units="g/ml"><xsl:value-of select="."/></float>
	    </xsl:when>
            <xsl:when test="@BUILTIN='DIPOLEMOMENT'">
        <float title="DipoleMoment" units="Debeye"><xsl:value-of select="."/></float>
	    </xsl:when>
          </xsl:choose>
        </xsl:for-each>
    </molecule>
  </xsl:template>

  <xsl:template match="FORMULA">
    <xsl:for-each select="XVAR">
      <xsl:choose>
      	<xsl:when test="@BUILTIN='MOLWT'">
        <float title="MolecularWeight" units="g/mol"><xsl:value-of select="."/></float>
	</xsl:when>
	<xsl:when test="@BUILTIN='STIOCHIOM'">
        <string title="Stoichiometry"><xsl:value-of select="."/></string>
	</xsl:when>
      </xsl:choose>
    </xsl:for-each>
  </xsl:template>
</xsl:stylesheet>
