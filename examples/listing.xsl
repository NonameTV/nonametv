<?xml version="1.0"?>
<xsl:stylesheet 
      xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
      version="1.0">
<xsl:output method="html"/>
  <xsl:template match="programme">
    <div class="programme"><b>
      <span class="startdate"><xsl:value-of select="substring(@start,1,8)"/><xsl:text> </xsl:text></span>
      <span class="starttime"><xsl:value-of select="substring(@start,9,2)"/>:<xsl:value-of select="substring(@start,11,2)"/> </span>
-
      <span class="enddate"><xsl:value-of select="substring(@stop,1,8)"/><xsl:text> </xsl:text></span>
      <span class="endtime"><xsl:value-of select="substring(@stop,9,2)"/>:<xsl:value-of select="substring(@stop,11,2)"/><xsl:text> </xsl:text></span>

      <span class="title"><xsl:value-of select="title/text()"/></span></b>
      <table>
        <tr>
          <td><b>start</b></td>
          <td><xsl:value-of select="@start"/></td>
        </tr>
        <tr>
          <td><b>stop</b></td>
          <td><xsl:value-of select="@stop"/></td>
        </tr>
        <xsl:apply-templates/>
      </table>
    </div>
  </xsl:template>

  <xsl:template match="programme//*">
    <tr>
      <td><b><xsl:value-of select="name()"/></b></td>
      <td><xsl:value-of select="text()"/></td>
    </tr>
    <xsl:apply-templates select="*"/>
  </xsl:template>

  <xsl:template match="programme//url">
    <tr>
      <td><b><xsl:value-of select="name()"/></b></td>
      <td><a><xsl:attribute name="href"><xsl:value-of select="text()"/></xsl:attribute><xsl:value-of select="text()"/></a></td>
    </tr>
  </xsl:template>
</xsl:stylesheet>
