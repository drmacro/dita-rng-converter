<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema"
  xmlns:xd="http://www.oxygenxml.com/ns/doc/xsl"
  xmlns:rng="http://relaxng.org/ns/structure/1.0"
  xmlns:rnga="http://relaxng.org/ns/compatibility/annotations/1.0"
  xmlns:rng2ditadtd="http://dita.org/rng2ditadtd"
  xmlns:relpath="http://dita2indesign/functions/relpath"
  xmlns:str="http://local/stringfunctions"
  xmlns:ditaarch="http://dita.oasis-open.org/architecture/2005/"
  xmlns:rngfunc="http://dita.oasis-open.org/dita/rngfunctions"
  xmlns:local="http://local-functions"
  exclude-result-prefixes="xs xd rng rnga relpath str ditaarch rngfunc local rng2ditadtd"
  version="2.0">
  
  <xd:doc scope="stylesheet">
    <xd:desc>
      <xd:p>RNG to DITA DTD Converter</xd:p>
      <xd:p><xd:b>Created on:</xd:b> Feb 16, 2013</xd:p>
      <xd:p><xd:b>Authors:</xd:b> ekimber, pleblanc</xd:p>
      <xd:p>This transform takes as input RNG-format DITA document type
        shells and produces DTD-syntax vocabulary modules
        that reflect the RNG definitions and conform to the DITA 1.3
        DTD coding requirements.
      </xd:p>
      <xd:p>The direct output is a conversion manifest, which simply
        lists the files generated. Each module and document type shell
        is generated separately using xsl:result-document.
      </xd:p>
      <xd:p>A note about generating text:</xd:p>
      <xd:p>In XSLT 2, xsl:value-of returns text nodes (in XSLT 1 it
      returned document nodes). In any context where strings would
      be concatenated, including for-each and for-each-group, if 
      you use xsl:sequence to return strings, the strings will be
      concatenated using the rules for string sequence concatenation,
      which means a blank will be inserted between each string. However,
      if you use xsl:value-of to return text nodes, there is no
      concatenation.</xd:p>
      <xd:p>This means that the code uses xsl:sequence *only* to return
      non-string, non-text nodes. Anywhere that the code generates
      literal strings it uses xsl:value-of.</xd:p>
      <xd:p>This transform can process either a single input RNG shell
        or an entire directory tree containing shells to process.</xd:p>
      <xd:p>To process a directory, omit the source document and 
      specify the initial template "processDir" and set the parameter
      rootDir to URI of the directory to process.</xd:p>
    </xd:desc>
  </xd:doc>
  
  <xsl:include href="../lib/relpath_util.xsl" />
  <xsl:include href="../lib/rng2functions.xsl"/>
  <xsl:include href="../lib/rng2gatherModules.xsl"/>
  <xsl:include href="../lib/rng2removeDivs.xsl"/>
  <xsl:include href="../lib/rng2normalize.xsl"/>
  <xsl:include href="../lib/rng2getReferencedModules.xsl"/>
  <xsl:include href="rng2ditashelldtd.xsl"/>
  <xsl:include href="rng2ditaent.xsl" />
  <xsl:include href="rng2ditamod.xsl" />
  <xsl:include href="rng2dtdOasisOverrides.xsl"/>  
  
  <!-- When true, turn on generation of modules, otherwise, only generate
       shells.
    -->
  <xsl:param name="generateModules" as="xs:string" select="'false'"/>
  <xsl:variable name="doGenerateModules" as="xs:boolean"
    select="matches($generateModules, 'true|yes|1|on', 'i')"
  />

  <!-- When true, allows generation of the standard modules, otherwise
       only generate non-standard modules.
    -->
  <xsl:param name="generateStandardModules" as="xs:string" select="'false'"/>
  <xsl:variable name="doGenerateStandardModules" as="xs:boolean"
    select="matches($generateStandardModules, 'true|yes|1|on', 'i')"
  />

  <!-- Output directory to put the generated DTD shell files in. 
      
       If not specified, output is relative to the input shell.
  -->
  <xsl:param name="outdir" as="xs:string" select="''"/>
  <!-- Output directory to put the generated DTD module files in.
       If not specified is the same as the output directory.
       This allows you to have shell DTDs go to one location and
       modules to another.
    -->
  <xsl:param name="moduleOutdir" as="xs:string" select="$outdir"/>
  
  <!-- Set this parameter to "as-is" to output the comments exactly
       as they are within the RNG documentation and header comment
       elements.
    -->
  <xsl:param name="headerCommentStyle" select="'comment-per-line'" as="xs:string"/>
  
  <!-- Controls whether or not DTDs and XSDs use public IDs or URNs
       to refer to included modules or use direct URLs.
    -->
  <xsl:param name="usePublicIDsInShell" as="xs:string"
    select="'true'"
  />

  <xsl:param name="ditaVersion" as="xs:string"
    select="'1.2'"
  />

  <xsl:param name="debug" as="xs:string" select="'false'"/>
  
  <xsl:param name="rootDir" as="xs:string" required="no"/>
      
  <xsl:variable name="doUsePublicIDsInShell" as="xs:boolean"
    select="matches($usePublicIDsInShell, 'yes|true|1|on', 'i')"
  />
  
  
  <!-- NOTE: The primary output of this transform is an XML 
       manifest file that lists all input files and their
       corresponding outputs.
    -->
  <xsl:output 
    method="xml"
    indent="yes"
  />

  <!-- Output method used to generate the DTD-syntax result files. -->
  <xsl:output name="dtd"
    method="text"
  />

  <xsl:variable name="doDebug" as="xs:boolean" 
    select="matches($debug, 'true|yes|on|1', 'i')" 
  />

  <xsl:strip-space elements="*"/>
  
  <xsl:key name="definesByName" match="rng:define" use="@name" />
  <xsl:key name="attlistIndex" match="rng:element" use="rng:ref[ends-with(@name, '.attlist')]/@name" />
  
  <xsl:template name="processDir">
    <!-- Template to process a directory tree. The "rootDir" parameter must
         be set, either the parent dir of the source document or explicitly
         specified as a runtime parameter.
      -->
     <xsl:call-template name="reportParameters"/>

    <xsl:message> + [INFO] Preparing documents to process...</xsl:message>
    <xsl:variable name="effectiveRootDir" as="xs:string" 
      select="if ($rootDir != '')
        then $rootDir
        else relpath:getParent(document-uri(root(.)))
      "/>
    <xsl:message> + [INFO] processDir: effectiveRootDir="<xsl:value-of select="$effectiveRootDir"/></xsl:message>
    <xsl:variable name="collectionUri" 
      select="concat($effectiveRootDir, '?', 
          'recurse=yes;',
          'select=*.rng'
          )" 
      as="xs:string"/>
    <xsl:variable name="rngDocs" as="document-node()*"
      select="collection(iri-to-uri($collectionUri))"
    />
    <xsl:if test="$doDebug">
      <xsl:message> + [DEBUG] rngDocs:
 <xsl:value-of select="for $doc in $rngDocs 
   return concat(relpath:getName(document-uri($doc)),
           ', moduleType: ',
           rngfunc:getModuleType($doc/*),
           ', isShell: ',
           rngfunc:isShellGrammar($doc),
           '&#x0a;')"/>
      </xsl:message>
    </xsl:if>
    <xsl:variable name="shellDocs" as="document-node()*"
      select="for $doc in $rngDocs 
      return if (rngfunc:isShellGrammar($doc))
                then $doc
                else ()
      "
    />
    <xsl:variable name="referencedModules" as="document-node()*">
      <xsl:for-each select="$shellDocs">
        <xsl:apply-templates mode="getIncludedModules" select="./*">
          <xsl:with-param name="doDebug" as="xs:boolean" tunnel="yes" select="$doDebug"/>
        </xsl:apply-templates>
      </xsl:for-each>
    </xsl:variable>
    
    <xsl:if test="$doDebug">
      <xsl:message> + [DEBUG] Referenced modules:
<xsl:sequence select="for $doc in $referencedModules return concat(document-uri($doc), '&#x0a;')"/>      
      </xsl:message>
    </xsl:if>    
    
    <xsl:variable name="moduleDocs" as="document-node()*"
      select="(for $doc in $rngDocs 
                return if (matches(string(document-uri($doc)), '.+Mod.rng'))
                          then $doc
                          else ()), 
                $referencedModules
      "
    />
    
    <xsl:if test="$doDebug">
      <xsl:message> + [DEBUG] Shell documents to process:</xsl:message>
        <xsl:message> + [DEBUG]</xsl:message>
        <xsl:for-each select="$shellDocs">
          <xsl:message> + [DEBUG]  <xsl:value-of 
            select="substring-after(string(document-uri(.)), concat($effectiveRootDir, '/'))"/></xsl:message>
        </xsl:for-each>
        <xsl:message> + [DEBUG]</xsl:message>
        <xsl:message> + [DEBUG] Module documents to process:</xsl:message>
        <xsl:message> + [DEBUG]</xsl:message>
        <xsl:for-each select="$moduleDocs">
          <xsl:message> + [DEBUG] - <xsl:value-of select="/*/ditaarch:moduleDesc/ditaarch:moduleTitle"/></xsl:message>
          <xsl:message> + [DEBUG]    <xsl:value-of 
            select="substring-after(string(document-uri(.)), concat($effectiveRootDir, '/'))"/></xsl:message>
        </xsl:for-each>
        <xsl:message> + [DEBUG]</xsl:message>
    </xsl:if>    
    
    <!-- Construct the set of all modules. This list may
         contain duplicates.
      -->

    <xsl:message> + [INFO] Getting list of unique modules...</xsl:message>
    <!-- Construct list of unique modules -->
    <xsl:variable name="modulesToProcess" as="document-node()*">
      <xsl:for-each-group select="$moduleDocs" group-by="string(document-uri(.))">
        <xsl:sequence select="."/><!-- Select first member of each group -->
      </xsl:for-each-group>
    </xsl:variable>
    <xsl:if test="$doDebug">
      <xsl:message> + [DEBUG] getReferencedModules: $modulesToProcess="<xsl:value-of select="for $mod in $modulesToProcess return rngfunc:getModuleShortName($mod/*)"/>"</xsl:message>      
    </xsl:if>
    
    <xsl:if test="count($modulesToProcess) = 0">
      <xsl:message terminate="yes"> - [ERROR] construction of modulesNoDivs failed. Count is <xsl:value-of select="count($modulesToProcess)"/>, should be greater than zero</xsl:message>
    </xsl:if>
    
    <xsl:message> + [INFO] Removing div elements from modules...</xsl:message>

    <!-- Now preprocess the modules to remove rng:div elements: -->
    <xsl:variable name="modulesNoDivs" as="document-node()*">
      <xsl:for-each select="$modulesToProcess">
         <xsl:apply-templates mode="removeDivs" select=".">
          <xsl:with-param name="doDebug" as="xs:boolean" tunnel="yes" select="$doDebug"/>
         </xsl:apply-templates>
      </xsl:for-each>
    </xsl:variable>
    
    <xsl:if test="count($modulesNoDivs) lt count($modulesToProcess)">
      <xsl:message terminate="yes"> - [ERROR] constructionof modulesNoDivs failed. Count is <xsl:value-of select="count($modulesNoDivs)"/>, should be <xsl:value-of select="count($modulesToProcess)"/></xsl:message>
    </xsl:if>
    
<!--    <xsl:message> + [DEBUG] Got <xsl:value-of select="count($modulesNoDivs)"/> modulesNoDivs.</xsl:message>-->
    
    <!-- NOTE: At this point, the modules have been preprocessed to remove
         <div> elements. This means that any module may be an intermediate
         document-node that has no associated document-uri() value. The @origURI
         attribute will have been added to the root element so we know where
         it came from.
      -->
    
    <xsl:variable name="dtdOutputDir" as="xs:string"
      select="if ($outdir = '') 
                 then relpath:newFile($effectiveRootDir, 'dtd') 
                 else relpath:getAbsolutePath($outdir)"
    />

    <xsl:message> + [INFO] Generating DTD files in output directory "<xsl:sequence select="$dtdOutputDir"/>"...</xsl:message>
    
    <rng2ditadtd:conversionManifest xmlns="http://dita.org/rng2ditadtd"
      timestamp="{current-dateTime()}"
      processor="{'rng2ditadtd.xsl'}"
      >
      <xsl:message> + [INFO] Generating shells...</xsl:message>
      <generatedShells>
        <xsl:if test="$doDebug">
          <xsl:message> + [DEBUG] applying templates to $shellDocs in mode processShell...</xsl:message>
        </xsl:if>
        <xsl:apply-templates 
          select="$shellDocs[($doGenerateStandardModules) or
                                   not(rngfunc:isStandardModule(.))]" 
          mode="processShell">
          <xsl:with-param name="dtdOutputDir" as="xs:string" tunnel="yes"
            select="$dtdOutputDir"
          />
          <xsl:with-param name="modulesToProcess" tunnel="yes" as="document-node()*"
            select="$modulesNoDivs"
          />
          <xsl:with-param name="doDebug" as="xs:boolean" tunnel="yes" select="$doDebug"/>         
        </xsl:apply-templates>
      </generatedShells>
      <xsl:message> + [INFO] Shells generated</xsl:message>
      <xsl:if test="$doGenerateModules">
        <xsl:message> + [INFO] =================================</xsl:message>
        <xsl:message> + [INFO] Generating .mod and .ent files in directory "<xsl:sequence select="$dtdOutputDir"/>"...</xsl:message>
        <generatedModules>
          <xsl:apply-templates 
            select="$modulesNoDivs[($doGenerateStandardModules) or
                                   not(rngfunc:isStandardModule(.))]" 
            mode="processModules">
            <xsl:with-param name="dtdOutputDir" as="xs:string" tunnel="yes"
              select="$dtdOutputDir"
            />
            <xsl:with-param name="modulesToProcess" tunnel="yes" as="document-node()*"
              select="$modulesToProcess"
            />
            <xsl:with-param name="doDebug" as="xs:boolean" tunnel="yes" select="$doDebug"/>         
          </xsl:apply-templates>
        </generatedModules>
      </xsl:if>
    </rng2ditadtd:conversionManifest>
    <xsl:message> + [INFO] Done.</xsl:message>
  </xsl:template>

  <xsl:template match="/">
    <xsl:call-template name="reportParameters"/>

    <xsl:variable name="dtdOutputDir" as="xs:string"
      select="if ($outdir = '') 
                 then relpath:newFile(relpath:getParent(relpath:getParent(relpath:getParent(string(base-uri(.))))), 'dtd') 
                 else relpath:getAbsolutePath($outdir)"
    />

    <xsl:variable name="modulesToProcess" as="document-node()*">
      <xsl:apply-templates mode="gatherModules" >
        <xsl:with-param name="origModule" select="root(.)"/>
        <xsl:with-param name="doDebug" as="xs:boolean" tunnel="yes" select="$doDebug"/>
      </xsl:apply-templates>
    </xsl:variable>
    
    <xsl:message> + [INFO] Removing div elements from modules...</xsl:message>
    
    <!-- Now preprocess the modules to remove rng:div elements: -->
    <xsl:variable name="modulesNoDivs" as="document-node()*">
      <xsl:for-each select="$modulesToProcess">
        <xsl:apply-templates mode="removeDivs" select=".">
          <xsl:with-param name="doDebug" as="xs:boolean" tunnel="yes" select="$doDebug"/>
        </xsl:apply-templates>
      </xsl:for-each>
    </xsl:variable>

    <!-- NOTE: At this point, the modules have been preprocessed to remove
         <div> elements. This means that any module may be an intermediate
         node that has no associated document-uri() value. The @origURI
         attribute will have been added to the root element so we know where
         it came from.
      -->
    
    <rng2ditadtd:conversionManifest xmlns="http://dita.org/rng2ditadtd"
      timestamp="{current-dateTime()}"
      processor="{'rng2ditadtd.xsl'}"
      >
      <generatedShells>
        <xsl:apply-templates select="." mode="processShell">
          <xsl:with-param name="dtdOutputDir" as="xs:string" tunnel="yes"
            select="$dtdOutputDir"
          />
          <xsl:with-param name="modulesToProcess" tunnel="yes" as="document-node()*"
            select="$modulesNoDivs"
          />
          <xsl:with-param name="doDebug" as="xs:boolean" tunnel="yes" select="$doDebug"/>         
        </xsl:apply-templates>
        
      </generatedShells>
      <xsl:if test="$doGenerateModules">
        <generatedModules>
          <xsl:apply-templates select="$modulesToProcess" mode="processModules">
            <xsl:with-param name="dtdOutputDir"
              select="$dtdOutputDir"
              tunnel="yes"
              as="xs:string"
            />
            <xsl:with-param name="modulesToProcess" as="document-node()*"
              tunnel="yes"
              select="$modulesToProcess"
            />          
          </xsl:apply-templates>
        </generatedModules>
      </xsl:if>  
    </rng2ditadtd:conversionManifest>
  </xsl:template>
  
  <xsl:template match="/" mode="processModules">    
   <xsl:param name="doDebug" as="xs:boolean" tunnel="yes" select="false()"/>

    <xsl:param 
      name="dtdOutputDir"
      tunnel="yes" 
      as="xs:string"
    />
    <xsl:variable name="rngModuleUrl" as="xs:string"
      select="if (*/@origURI) then */@origURI else base-uri(.)"
    />
    <xsl:message> + [INFO] processModules: Handling module <xsl:value-of select="$rngModuleUrl"/>...</xsl:message>
    <xsl:if test="$doDebug">
      <xsl:message> + [DEBUG] generate-modules: rngModuleUrl="<xsl:sequence
        select="$rngModuleUrl"/>"</xsl:message>
    </xsl:if>
    <!-- Use the RNG module's grandparent directory name to construct output
         dir so the DTD module organization mirrors the RNG organization.
         This should always do the right thing for the OASIS-provided 
         modules.
         
         The general file organization pattern for OASIS-provided vocabulary files 
         is:
         
         doctypes/{packagename}/{typename}/{module file}
         
         e.g.:
         
         doctypes/base/rng/topicMod.rng
         doctypes/base/dtd/topic.mod
         
      -->
    <xsl:variable name="packageName" as="xs:string"
      select="relpath:getName(relpath:getParent(relpath:getParent($rngModuleUrl)))"
    />

    <!-- Put the DTD files in a directory named "dtd/" -->
    <xsl:variable name="resultDir"
      select="relpath:toUrl(relpath:newFile(relpath:newFile($dtdOutputDir, $packageName), 'dtd'))"
    />
    <xsl:if test="$doDebug">
      <xsl:message> + [DEBUG] generate-modules: resultDir="<xsl:sequence select="$resultDir"/>"</xsl:message>
    </xsl:if>

    <xsl:variable name="rngModuleName" as="xs:string"
      select="relpath:getNamePart($rngModuleUrl)" />
    <xsl:variable name="moduleBaseName" as="xs:string"
      select="if (ends-with($rngModuleName, 'Mod')) 
      then substring-before($rngModuleName, 'Mod') 
      else $rngModuleName"
    />
    <xsl:variable name="entFilename" as="xs:string"
      select="rngfunc:getEntityFilename(./*, 'ent')"
    />
    <xsl:variable name="modFilename" as="xs:string"
      select="rngfunc:getEntityFilename(./*, 'mod')"
    />
    <xsl:variable name="moduleType" as="xs:string"
      select="rngfunc:getModuleType(./*)"
    />
    <xsl:variable name="moduleShortName" as="xs:string"
      select="rngfunc:getModuleShortName(./*)"
    />
    <xsl:variable name="entResultUrl"
      select="relpath:newFile($resultDir, $entFilename)" />
    <xsl:variable name="modResultUrl"
      select="relpath:newFile($resultDir, $modFilename)" />

    <!-- Now generate the .mod and .ent files: -->

    <moduleFiles xmlns="http://dita.org/rng2ditadtd">
      <inputFile><xsl:sequence select="$rngModuleUrl" /></inputFile>
      <entityFile><xsl:sequence select="$entResultUrl" /></entityFile>
      <modFile><xsl:sequence select="$modResultUrl" /></modFile>
    </moduleFiles>
    <!-- Generate the .ent file: -->
    <!-- NOTE: Not all base modules have .ent files -->
    <xsl:if test="
      not($moduleShortName = 
      ('tblDecl', 
       'metaDecl', 
       'map'))"
      >    
      <xsl:if test="$doDebug">
        <xsl:message> + [DEBUG] processModules: Applying templates in mode entityFile to generate "<xsl:value-of select="$entResultUrl"/>"</xsl:message>
      </xsl:if>
      <xsl:if test="not($moduleType = ('constraint'))">
        <xsl:result-document href="{$entResultUrl}" format="dtd">
          <xsl:apply-templates mode="entityFile">
            <xsl:with-param name="dtdFilename" as="xs:string" tunnel="yes" select="$entFilename"/>
          </xsl:apply-templates>        
        </xsl:result-document>
      </xsl:if>
    </xsl:if>
    <!-- Generate the .mod file: NOTE: Attribute modules only have .ent files -->
    <xsl:if test="not($moduleType = ('attributedomain'))">
      <xsl:if test="$doDebug">
        <xsl:message> + [DEBUG] processModules: Applying templates in mode moduleFile to generate "<xsl:value-of select="$modResultUrl"/>"</xsl:message>
      </xsl:if>
      <xsl:result-document href="{$modResultUrl}" format="dtd">
        <xsl:apply-templates mode="moduleFile" >
          <xsl:with-param name="dtdFilename" as="xs:string" tunnel="yes" select="$modFilename"/>
        </xsl:apply-templates>
      </xsl:result-document>
    </xsl:if>
    
  </xsl:template>
  
  <xsl:template mode="#all" match="rng:define[@name = 'idElements']" priority="100">
    <!-- This pattern is only relevant to RNG and RNC grammars. Suppress it in the DTDs
      -->
  </xsl:template>

  <!-- ==============================
       Other modes and functions
       ============================== -->

  <xsl:template match="text()" mode="#all" priority="-1" />

  <xsl:template match="rng:*" priority="-1" mode="entityFile">
    <xsl:message> - [WARN] entityFile: Unhandled RNG element <xsl:sequence select="concat(name(..), '/', name(.))" /></xsl:message>
  </xsl:template>

  <xsl:template match="rng:*" priority="-1" mode="element-decls">
    <xsl:message> - [WARN] element-decls: Unhandled RNG element <xsl:sequence select="concat(name(..), '/', name(.))" /><xsl:copy-of select="." /></xsl:message>
  </xsl:template>
  <xsl:template match="rng:*" priority="-1" mode="element-name-entities">
    <xsl:message> - [WARN] element-name-entities: Unhandled RNG element <xsl:sequence select="concat(name(..), '/', name(.))" /><xsl:copy-of select="." /></xsl:message>
  </xsl:template>
  <xsl:template match="rng:*" priority="-1" mode="class-att-decls">
    <xsl:message> - [WARN] class-att-decls: Unhandled RNG element <xsl:sequence select="concat(name(..), '/', name(.))" /><xsl:copy-of select="." /></xsl:message>
  </xsl:template>
  
  <xsl:template match="rng:div" mode="#all">
    <!-- RNG div elements are "transparent" and have no special meaning
         for DTD output (except possibly in a few special cases) 
         
         Note that this is really here for safety since we filter out
         all the divs before doing any output processing once we have
         gathered the modules to be processed.
      -->
    <xsl:apply-templates mode="#current"/>
  </xsl:template>
  
  <xsl:template name="reportParameters">
<xsl:message> + [INFO] Parameters:
  
  debug              ="<xsl:value-of select="$debug"/>"
  ditaVersion        ="<xsl:value-of select="$ditaVersion"/>"
  generateModules    ="<xsl:value-of select="concat($generateModules, ' (', $doGenerateModules, ')')"/>"
  headerCommentStyle ="<xsl:value-of select="$headerCommentStyle"/>"
  moduleOutdir       ="<xsl:value-of select="$moduleOutdir"/>"
  outdir             ="<xsl:value-of select="$outdir"/>"
  usePublicIDsInShell="<xsl:value-of select="concat($usePublicIDsInShell, ' (', $doUsePublicIDsInShell, ')')"/>"

</xsl:message>    
    
    
  </xsl:template>

</xsl:stylesheet>