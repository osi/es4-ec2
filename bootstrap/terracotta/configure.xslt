<?xml version="1.0" encoding="UTF-8" ?>
<xsl:stylesheet version="1.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

    <xsl:output encoding="UTF-8" indent="yes" method="xml" />
    
    <xsl:param name="hostname"/>
    <xsl:param name="id"/>

    <xsl:template match="servers">
        <servers>
            <server name="{$id}" host="{$hostname}">
                <data>%(user.home)/terracotta/server-data</data>
                <logs>%(user.home)/terracotta/server-logs</logs>
            </server>
        </servers>
    </xsl:template>

    <xsl:template match="node()|@*">
        <xsl:copy>
            <xsl:apply-templates select="@*"/>
            <xsl:apply-templates/>
        </xsl:copy>
    </xsl:template>
</xsl:stylesheet>
