<?xml version="1.0"?>
<xsl:stylesheet 
      xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
      version="1.0">
  <xsl:template match="tv">
      <select name="channel">
        <xsl:apply-templates/>
      </select>
  </xsl:template>
  <xsl:template match="channel">
    <option>
      <xsl:attribute name="value">
        <xsl:value-of select="@id"/>
      </xsl:attribute>
      <xsl:value-of select="display-name/text()"/>
    </option>
  </xsl:template>
</xsl:stylesheet>