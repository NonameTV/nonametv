<?xml version="1.0"?>
<xsl:stylesheet 
      xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
      version="1.0">
<xsl:output method="html" encoding="ISO-8859-1"/>
<xsl:strip-space elements="*"/>
  <xsl:template match="tv">
    <html><head>
      <title>Available Channels</title>
    </head>
    <body>
      <h1>Available Channels</h1>
      <p>The following channels are available from xmltv.se:</p>
      <div id="channels">
        <ul>
        <xsl:apply-templates>
          <xsl:sort select="display-name/text()"/>
        </xsl:apply-templates>
        </ul>
      </div>
     </body></html>
  </xsl:template>
  <xsl:template match="channel">
      <li><xsl:value-of select="display-name/text()"/></li>
  </xsl:template>
</xsl:stylesheet>
