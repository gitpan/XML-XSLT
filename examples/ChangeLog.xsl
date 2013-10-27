<?xml version="1.0" encoding="iso-8859-1"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                version="1.0">
  <xsl:template match="/">
     <html xmlns="http://www.w3.org/1999/xhtml">
        <head>
          <title>XML::XSLT Changelog</title>
          <link type="text/css" rel="stylesheet" href="xslt.css" />
          <style type="text/css">
            body {
                   background-color: white;
                 }
          </style>
       </head>
       <body>
         <table summary="" border="0" cellpadding="0" cellspacing="7">
           <tr>
             <td width="130" valign="top">
               <table summary="" 
                      border="0" 
                      class="nav" 
                      cellpadding="0"
                      cellspacing="0">
                 <tr>
                   <td valign="top">
                     <img src="bluedot.gif" 
                          width="20"
                          height="20" 
                          alt="*" 
                          align="middle" />
                   </td>

                   <td><a href="./">Home</a></td>
                 </tr>

                 <tr>
                   <td valign="top">
                      <img src="bluedot.gif" 
                           width="20"
                           height="20" 
                           alt="*" 
                           align="middle" />
                   </td>
                   <td>
                     <a href="http://www.sourceforge.net/projects/xmlxslt/">
                       Project info
                     </a>
                   </td>
                 </tr>

                 <tr>
                   <td valign="top">
                      <img src="bluedot.gif" 
                           width="20"
                           height="20" 
                           alt="*" 
                           align="middle" />
                   </td>
                   <td>
                      <a href="manpage-XML-XSLT.html">
                         XML::XSLT manpage
                      </a>
                   </td>
                 </tr>
                 <tr>
                   <td valign="top">
                      <img src="bluedot.gif" 
                           width="20"
                           height="20" 
                           alt="*" 
                           align="middle" />
                   </td>
                   <td>
                      <a href="http://sourceforge.net/project/showfiles.php?group_id=6054">
                         Download
                      </a>
                   </td>
                 </tr>

                 <tr>
                   <td valign="top">
                     <img src="bluedot.gif" 
                          width="20"
                          height="20" 
                          alt="*" 
                          align="middle" />
                   </td>
                   <td>
                      <a href="./#examples">
                        Examples
                      </a>
                   </td>
                 </tr>

                 <tr>
                   <td valign="top">
                      <img src="bluedot.gif" 
                           width="20"
                           height="20" 
                           alt="*" 
                           align="middle" />
                   </td>
                   <td>
                      <a href="./#links">
                        Links
                      </a>
                   </td>
                 </tr>

                 <tr>
                   <td colspan="2">
                     <br />
                     <hr />
                     <br />
                     <strong>Mailing list:</strong><br />
                     <a
                     href="http://lists.sourceforge.net/mailman/listinfo/xmlxslt-discuss">
                     xmlxslt-discuss@lists.sourceforge.net</a><br />
                     <em>This list is archived at <a
                     href="http://www.geocrawler.com/lists/3/SourceForge/4508/0/">
                     GeoCrawler</a>.</em><br />
                     <br />
                     <hr />
                     <br />
                     <a
                     href="http://validator.w3.org/check/referer"><img
                     border="0"
                     src="http://www.w3.org/Icons/valid-xhtml10"
                     alt="Valid XHTML 1.0!" height="31" width="88" /></a>
                     <a href="http://sourceforge.net"><img
                     src="http://sourceforge.net/sflogo.php?group_id=6054&amp;type=1"
                      width="88" height="31" border="0"
                     alt="SourceForge" /></a> 
                   </td>
                 </tr>
               </table>
             </td>

             <td width="1" bgcolor="black"><img src="black1x1.gif"
             width="1" height="1" alt="|" /></td>

             <td valign="top">
                <h1>XML::XSLT Changelog</h1>
                <xsl:apply-templates select="changelog/entry"/>
             </td>
           </tr>
         </table>
       </body>
     </html>
   </xsl:template>
   <xsl:template match="entry">
      <div class="section">
        <h2><xsl:value-of select="date" /><xsl:text> </xsl:text>
            <xsl:value-of select="time" /><xsl:text> </xsl:text>
            <xsl:value-of select="author" />
        </h2>
        <div class="container">
           <ul type="disc">
                 <xsl:apply-templates select="msg/item" />
           </ul> 
        </div>
      </div>   
   </xsl:template>
   <xsl:template match="entry/msg/item">
     <li>
       <xsl:apply-templates />
     </li>
   </xsl:template>
</xsl:stylesheet>
